# rubocop:disable all

require 'faraday'
require 'telegram/bot'
require "eventmachine"
require 'faye/websocket'
require 'httplog'
require_relative 'models'

@secret = 'GahrtTE4HB3D5lDJMrVexG5vYGmXH4aby6AvsWLpQtMBnKqtF4rMdwi01RtyvIwJ'
@api_key = 'Kxik049wUogM9WuntnfgApKb47o1MXL4rPKvTkBuPRCnK5Iz75wqPSYhpvWbZbyQ'
@amount_usdt = 10

@bot_token = '5386548110:AAGzvQuthMfB15Tfyk8f2vsIYyH-AmmltWY'


@fapi_conn = Faraday.new(
  url: 'https://fapi.binance.com',
  headers: { 'X-MBX-APIKEY' => @api_key }
){|f| f.request :url_encoded }

def tg_notify(msg)
  Telegram::Bot::Client.run(@bot_token) do |bot|
    bot.api.send_message(chat_id: '-818755305', text: msg)
  end
end

def cancel_order(symbol)
  body = "symbol=#{symbol}&timestamp=#{Time.now.strftime('%s%L')}"
  sign = OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
  response = @fapi_conn.delete("/fapi/v1/allOpenOrders") do |req|
    req.body = body + '&signature=' + sign
  end
  if response.status != 200
    tg_notify("#{symbol} CANCELING ORDER ERROR #{response.body}")
  end
end

def place_stop_market_order(symbol, side, stop_price, quantity)
  stop_price = stop_price.round($pairs[symbol]['precision'])
  body = "symbol=#{symbol}&side=#{side}&type=STOP_MARKET&timeInForce=GTC&priceProtect=true&closePosition=true&stopPrice=#{stop_price}&timestamp=#{Time.now.strftime('%s%L')}"
  sign = OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
  response = @fapi_conn.post("/fapi/v1/order") do |req|
    req.body = body + '&signature=' + sign
  end
  if response.status != 200
    place_market_order(symbol, side, quantity)
    tg_notify("Place stop market order #{symbol} Response error. #{response.body}")
  end
end

def place_batch_orders(symbol, side, current_price, quantity, p)
  leverage = $pairs[symbol]['leverage']
  percent = (100.to_f / leverage).round(2)
  operations = ->(o_t){ ['+', '-'].rotate(o_t == "SELL" ? 1 : 0) }.call(side)
  l1 = { price: current_price.send(operations.last, current_price * (percent * p) / 100).round($pairs[symbol]['precision']), quantity: (quantity).round($pairs[symbol]['qty_precision']) }
  # l2 = { price: current_price.send(operations.last, current_price * (percent * 0.5) / 100).round(@pairs[symbol]['precision']), quantity: ((quantity - l1[:quantity]) / 2).round(@pairs[symbol]['qty_precision']) }
  # l3 = { price: current_price.send(operations.last, current_price * (percent) / 100).round(@pairs[symbol]['precision']), quantity: (l2[:quantity]).round(@pairs[symbol]['qty_precision']) }
  body = "batchOrders=[
    { \"symbol\": \"#{symbol}\", \"side\": \"#{side}\", \"type\": \"LIMIT\", \"price\": \"#{l1[:price]}\", \"quantity\": \"#{l1[:quantity]}\", \"timeInForce\": \"GTC\"}
  ]&timestamp=#{Time.now.strftime('%s%L')}".gsub(/\s/, "")
  sign = OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
  response = @fapi_conn.post("/fapi/v1/batchOrders") do |req|
    req.body = body + '&signature=' + sign
  end
  if response.status != 200
    tg_notify("Place batch orders #{symbol} Response error. #{response.body}")
  end
end

def place_market_order(symbol, side, quantity)
  body = "symbol=#{symbol}&side=#{side}&type=MARKET&quantity=#{quantity}&timestamp=#{Time.now.strftime('%s%L')}"
  sign = OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
  response = @fapi_conn.post("/fapi/v1/order") do |req|
    req.body = body + '&signature=' + sign
  end
  if response.status != 200
    $pairs[symbol]['wall'] = {}
    message = "MARKET ORDER ERROR #{symbol}.\n#{response.body}"
    tg_notify(message)
  end
end




response = @fapi_conn.get('/fapi/v1/exchangeInfo')
body = JSON.parse(response.body)
body["symbols"].each do |symbol|
  $pairs[symbol["symbol"]]['qty_precision'] = symbol["quantityPrecision"] if $pairs[symbol["symbol"]]
end

