require_relative 'message_delivery'

module ChatProtocol
  import MessageDelivery => :network

  state do
    interface input, :set_ipport, [:ipport]
    table :ifaces, [:id, :ipp]

    scratch :messages, [:msg]
    scratch :r_node_inform, [:addr, :lifetime]
    scratch :s_node_inform, [:rcv, :msg]
    scratch :r_request_node_list, [:addr]
    scratch :s_request_node_list, [:rcv, :msg]
    scratch :r_user_connect, [:addr, :lifetime]
    scratch :s_user_connect, [:rcv, :msg]
    scratch :r_user_disconnect, [:addr]
    scratch :s_user_disconnect, [:rcv, :msg]
    scratch :c_user_disconnect, [:rcv, :msg]
    scratch :r_user_message, [:addr, :nick, :time, :text]
    scratch :s_user_message, [:rcv, :msg]
    scratch :r_heartbeat, [:addr]
    scratch :s_heartbeat, [:rcv]
    scratch :c_heartbeat, [:rcv]

    scratch :s_new_message, [:rcv, :msg]
    scratch :r_new_message, [:id, :timestamp, :data]
    scratch :s_new_message_relation, [:rcv, :msg]
    scratch :r_new_message_relation, [:id, :target]
  end

  bloom :setup do
    ifaces <= set_ipport { |x| [0, x[0]] }
  end

  bloom :receive_network do
    messages <= network.received
    r_node_inform <= messages { |x| x.msg.drop(1) if x.msg[0] == "NODE_INFORM" }
    r_request_node_list <= messages { |x| x.msg.drop(1) if x.msg[0] == "REQUEST_NODE_LIST" }
    r_user_connect <= messages { |x| x.msg.drop(1) if x.msg[0] == "USER_CONNECT" }
    r_user_disconnect <= messages { |x| x.msg.drop(1) if x.msg[0] == "USER_DISCONNECT" }
    r_user_message <= messages { |x| x.msg.drop(1) if x.msg[0] == "USER_MESSAGE" }
    r_heartbeat <= messages { |x| x.msg.drop(1) if x.msg[0] == "HEARTBEAT" }
    r_new_message <= messages { |x| x.msg.drop(1) if x.msg[0] == "NEW_MESSAGE" }
    r_new_message_relation <= messages { |x| x.msg.drop(1) if x.msg[0] == "NEW_MESSAGE_RELATION" }
  end

  bloom :send_network do
    network.push <= (ifaces * s_node_inform).pairs { |iface, x| [iface.ipp, x.rcv, ["NODE_INFORM"] + x.msg] }
    network.push <= (ifaces * s_request_node_list).pairs { |iface, x| [iface.ipp, x.rcv, ["REQUEST_NODE_LIST"] + x.msg] }
    network.push <= (ifaces * s_user_connect).pairs { |iface, x| [iface.ipp, x.rcv, ["USER_CONNECT"] + x.msg] }
    network.push <= (ifaces * s_user_disconnect).pairs { |iface, x| [iface.ipp, x.rcv, ["USER_DISCONNECT"] + x.msg] }
    network.push <= (ifaces * s_user_message).pairs { |iface, x| [iface.ipp, x.rcv, ["USER_MESSAGE"] + x.msg] }
    network.push <= (ifaces * s_heartbeat).pairs { |iface, x| [iface.ipp, x.rcv, ["HEARTBEAT"]] }
    network.push <= (ifaces * s_new_message).pairs { |iface, x| [iface.ipp, x.rcv, ["NEW_MESSAGE"] + x.msg] }
    network.push <= (ifaces * s_new_message_relation).pairs { |iface, x| [iface.ipp, x.rcv, ["NEW_MESSAGE_RELATION"] + x.msg] }
  end

  bloom :confirm_network do
    c_heartbeat <= network.confirmed { |x| [x.dst] if x.data[0] == "HEARTBEAT" }
    c_user_disconnect <= network.confirmed { |x| [x.dst, x.data.drop(1)] if x.data[0] == "USER_DISCONNECT" }
  end
end