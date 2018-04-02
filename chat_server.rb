require 'rubygems'
require 'backports'
require 'bud'
require_relative 'message_delivery'
require_relative 'chat_protocol'

DEFAULT_ADDR = "127.0.0.1:12345"

class ChatServer
  include Bud
  import ChatProtocol => :proto

  state do
    table :peers, [:addr]
    scratch :new_peers, [:addr]

    periodic :heartbeat_timer, 5.0
    table :heartbeat_sendtimes, [:addr, :time]
    scratch :dead_peers, [:addr, :beat_count]
  end

  bootstrap do
    proto.set_ipport <= [[ip_port]]
  end

  bloom do
    new_peers <= proto.r_server_connect.notin(peers)
    peers <+ new_peers
    proto.s_user_connect <+ (peers * new_peers).pairs { |p, c| [c.addr, [p.addr]] } # Tell the newly joined peer of all peers
    proto.s_user_connect <+ (peers * new_peers).pairs { |p, c| [p.addr, [c.addr]] } # Tell all other peers of the new one
    stdio <~ new_peers { |c| [ "User " + c.addr + " connected" ] }

    # Heartbeating.
    #heartbeat <~ server_connect { |u| [u.addr, ip_port] }
    #heartbeat_sendtimes <+- server_connect { |u| [u.addr, Time.now.to_f] }
    #heartbeat <~ heartbeat { |p| [p.addr, ip_port] }
    #heartbeat_sendtimes <+- heartbeat { |u| [u.addr, Time.now.to_f] }
    # Clear out dead peers
    #dead_peers <= (heartbeat_timer * heartbeat_sendtimes).flat_map { |_, m| if Time.now.to_f >= m.time + 10.0 then [m] else [] end }
    #heartbeat_sendtimes <- dead_peers
    #peers <- dead_peers { |m| [m.addr] }
    #stdio <~ dead_peers { |u| ["User " + u.addr + " died"] }
  end
end

# ruby command-line wrangling
addr = (ARGV.length == 2) ? ARGV[1] : DEFAULT_ADDR
ip, port = addr.split(":")
puts "Server address: #{ip}:#{port}"
if ARGV[0] == "run"
  program = ChatServer.new(:ip => ip, :port => port.to_i)
  program.run_fg
end