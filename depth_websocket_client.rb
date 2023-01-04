require_relative 'wall_finder'

@depth_params = $pairs.keys.map { |symbol| "#{symbol.downcase}@depth" }


def depth_connection
  ws = Faye::WebSocket::Client.new('wss://stream.binance.com:9443/stream', nil, ping: 180, headers: { 'X-MBX-APIKEY' => @api_key })

  ws.on :open do |event|
    puts [:open]
    ws.send({ method: "SUBSCRIBE", params: @depth_params, id: 1 }.to_json)
  end

  ws.on :message do |event|
    data = JSON.parse(event.data)
    next if data.keys.include?("result")

    ["b", "a"].each do |o_type|
      data["data"][o_type].each do |order_data|
        price = order_data.first.to_f
        quantity = order_data.last.to_f
        vol = price * quantity
        symbol = data["data"]["s"]
        ActiveRecord::Base.logger = nil
        if vol >= $pairs[symbol]["volume"]
          ActiveRecord::Base.transaction do
            book_order = BookOrder.find_or_initialize_by(symbol: symbol, price: price, side: o_type)
            book_order.quantity = quantity
            book_order.save
          end
        else
          BookOrder.where(symbol: symbol, price: price, side: o_type).destroy_all
        end
        ActiveRecord::Base.logger = Logger.new(STDOUT)
      end
    end
  end

  ws.on :close do |event|
    puts [:close, event.code, event.reason, "DEPTH"]
    depth_connection
  end
end

EM.run do
  depth_connection
end
