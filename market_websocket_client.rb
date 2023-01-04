require_relative 'wall_finder'

@params = $pairs.keys.map { |symbol| "#{symbol.downcase}@bookTicker" }

def ticket_connection
  ws = Faye::WebSocket::Client.new('wss://stream.binance.com:9443/stream', nil, ping: 60, headers: { 'X-MBX-APIKEY' => @api_key })

  ws.on :open do |event|
    puts [:open, Time.now]
    ws.send({ method: "SUBSCRIBE", params: @params, id: 1 }.to_json)
  end

  ws.on :message do |event|
    data = JSON.parse(event.data)
    next if data.keys.include?("result")

    update_id = data['data']['u']
    bid_price = data['data']['b'].to_f
    bid_quantity = data['data']['B'].to_f
    ask_price = data['data']['a'].to_f
    ask_quantity = data['data']['A'].to_f
    bid_vol = bid_price * bid_quantity
    ask_vol = ask_price * ask_quantity
    symbol = data['data']['s']
    ActiveRecord::Base.logger = nil
    wall = Wall.where.not(status: :finish).find_by(symbol: symbol)
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    if wall && wall.update_id < update_id
      if wall.bid?
        if bid_price == wall.price.to_f && (wall.wall_quantity / bid_quantity) >= 10
          if wall.last_order_side == 'buy'
            current_quantity = wall.current_quantity
            wall.update(last_order_side: 'sell', update_id: update_id, current_quantity: wall.initial_quantity)
            place_market_order(symbol, 'SELL', wall.initial_quantity + current_quantity)
            tg_notify("WALL ALMOST PIERCED ##{symbol}!\n Current quantity: #{ask_quantity}")
          end
        elsif bid_price < wall.price.to_f
          if wall.last_order_side == 'buy'
            current_quantity = wall.current_quantity
            wall.update(last_order_side: 'sell', update_id: update_id, current_quantity: wall.initial_quantity)
            place_market_order(symbol, 'SELL', wall.initial_quantity + current_quantity)
            tg_notify("WALL PIERCED #{symbol}")
          end
        end
      elsif wall.ask?
        if ask_price == wall.price.to_f && (wall.wall_quantity / ask_quantity) >= 10
          if wall.last_order_side == 'sell'
            current_quantity = wall.current_quantity
            wall.update(last_order_side: 'buy', update_id: update_id, current_quantity: wall.initial_quantity)
            place_market_order(symbol, 'BUY', wall.initial_quantity + current_quantity)
            tg_notify("WALL ALMOST PIERCED ##{symbol}!\n Current quantity: #{ask_quantity}")
          end
        elsif ask_price > wall.price.to_f
          if wall.last_order_side == 'sell'
            current_quantity = wall.current_quantity
            wall.update(last_order_side: 'buy', update_id: update_id, current_quantity: wall.initial_quantity)
            place_market_order(symbol, 'BUY', wall.initial_quantity + current_quantity)
            tg_notify("WALL PIERCED #{symbol}")
          end
        end
      end
    elsif bid_vol > $pairs[symbol]["volume"]
      book_order = BookOrder.find_by(price: bid_price, side: "b", symbol: symbol, status: :wall)
      if book_order && (Time.now.utc - book_order.status_changed_at) > 20
        leverage = $pairs[symbol]['leverage']
        quantity = ((@amount_usdt * leverage) / ask_price).round($pairs[symbol]['qty_precision'])
        Wall.create(symbol: symbol, price: bid_price, side: :bid, last_order_side: 'buy', update_id: update_id, wall_quantity: bid_quantity,  initial_quantity: quantity, current_quantity: quantity, book_order: book_order )
        place_market_order(symbol, 'BUY', quantity)
        tg_notify("WALL FOUND ##{symbol}!\nType: BID\nPrice: #{bid_price}\nQuantity: #{bid_quantity}\nVol: #{bid_vol}$")
      end
    elsif ask_vol > $pairs[symbol]["volume"]
      book_order = BookOrder.find_by(price: ask_price, side: "a", symbol: symbol, status: :wall)
      if book_order && (Time.now.utc - book_order.status_changed_at) > 20
        leverage = $pairs[symbol]['leverage']
        quantity = ((@amount_usdt * leverage) / bid_price).round($pairs[symbol]['qty_precision'])
        Wall.create(symbol: symbol, price: ask_price, side: :ask, last_order_side: 'sell', update_id: update_id, wall_quantity: ask_quantity, initial_quantity: quantity, current_quantity: quantity, book_order: book_order )
        place_market_order(symbol, 'SELL', quantity)
        tg_notify("WALL FOUND ##{symbol}!\nType: ASK\nPrice: #{ask_price}\nQuantity: #{ask_quantity}\nVol: #{ask_vol}$")
      end
    end
  end

  ws.on :close do |event|
    puts [:close, event.code, event.reason, "Market Stream", Time.now]
    ticket_connection
  end
end

EM.run do
  ticket_connection
end
