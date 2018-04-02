
module MessageDelivery
  state do
    interface input, :push, [:src, :dst, :data]
    interface output, :confirmed, [:src, :dst, :data]
    interface output, :received, [:data]

    channel :msg_send, [:@addr, :msg] => []
    channel :msg_confirm, [:@addr, :msg] => []

    table :messages, [:src, :dst, :data]
    periodic :clock, 5.0
  end

  bloom do
    # Collect messages for pushing
    messages <= push

    # Send all messages instantly and at a clock tick
    msg_send <~ push { |x| [x.dst, x] }
    msg_send <~ (clock * messages).rights { |x| [x.dst, x] }

    # Collect on a succesful send
    confirmed <= msg_confirm { |x| x.msg }
    messages <- confirmed

    # Answer to a received message and pass it on.
    received <= msg_send { |x| [x.msg[2]] }
    msg_confirm <~ msg_send { |x| [x.msg[0], x.msg] }

    #stdio <~ push { |x| ["Pushed network message: " + x.to_s] }
    #stdio <~ msg_send { |x| ["Received network message: " + x.msg[2].to_s] }
    #stdio <~ confirmed { |x| ["Successfully sent network message: " + x.to_s] }
  end
end
