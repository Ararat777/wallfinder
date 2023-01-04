require_relative 'wall_finder'

response = @fapi_conn.post('/fapi/v1/listenKey')
@json = JSON.parse(response.body)

def account_connection
  ws = Faye::WebSocket::Client.new("wss://fstream.binance.com/ws/#{@json['listenKey']}", nil, ping: 180)

  ws.on :open do |event|
    puts [:open]
  end

  ws.on :message do |event|
    data = JSON.parse(event.data)
    if data['e'] == 'ORDER_TRADE_UPDATE' && data['o']['X'] == 'FILLED'
      symbol = data['o']['s']
      order_type = data['o']['o']
      order_side = data['o']['S']
      price = data['o']['ap'].to_f
      wall = Wall.where.not(status: :finish).find_by(symbol: symbol)
      if wall
        if order_type == 'MARKET'
          if order_side == "BUY"
            if wall.bid?
              if wall.created?
                wall.in_progress!
                Order.create(price: price, side: order_side, order_type: order_type, quantity: wall.current_quantity, wall: wall)
                place_batch_orders(symbol, "SELL", price, wall.current_quantity, 0.25)
                tg_notify("MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              elsif wall.in_progress?
                wall.finish!
                cancel_order(symbol)
                tg_notify("FINISH MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              end
            elsif wall.ask?
              if wall.in_progress?
                cancel_order(symbol)
                Order.create(price: price, side: order_side, order_type: order_type, quantity: wall.current_quantity, wall: wall)
                place_stop_market_order(symbol, "SELL", price * 0.999, wall.current_quantity)
                place_batch_orders(symbol, "SELL", price, wall.current_quantity, 0.4)
                tg_notify("MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              end
            end
          elsif order_side == "SELL"
            if wall.bid?
              if wall.in_progress?
                cancel_order(symbol)
                Order.create(price: price, side: order_side, order_type: order_type, quantity: wall.current_quantity, wall: wall)
                place_stop_market_order(symbol, "BUY", price * 1.001, wall.current_quantity)
                place_batch_orders(symbol, "BUY", price, wall.current_quantity, 0.4)
                tg_notify("MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              end
            elsif wall.ask?
              if wall.created?
                wall.in_progress!
                Order.create(price: price, side: order_side, order_type: order_type, quantity: wall.current_quantity, wall: wall)
                place_batch_orders(symbol, "BUY", price, wall.current_quantity, 0.25)
                tg_notify("MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              elsif wall.in_progress?
                wall.finish!
                cancel_order(symbol)
                tg_notify("FINISH MARKET ORDER #{symbol} #{order_side}\nPrice: #{price}")
              end
            end
          end
        elsif order_type == "LIMIT"
          quantity = data['o']['q'].to_f
          Order.create(price: price, side: order_side, order_type: order_type, quantity: quantity, wall: wall)
          cancel_order(symbol)
          wall.finish!
          tg_notify("FINISH LIMIT ORDER #{symbol} #{order_side}\nPrice: #{price}")
        end
      end
    end
  end

  ws.on :close do |event|
    puts [:close, event.code, event.reason, "Account Stream"]
    response = @fapi_conn.post('/fapi/v1/listenKey')
    @json = JSON.parse(response.body)
    account_connection
  end
end
thread1 = Thread.new do
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  EM.run do
    account_connection
  end
end

thread2 = Thread.new do
  loop do
    sleep(3000)
    @fapi_conn.put('/fapi/v1/listenKey')
  end
end


thread1.join
thread2.join
