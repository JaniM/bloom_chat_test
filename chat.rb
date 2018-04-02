require 'rubygems'
require 'backports'
require 'bud'
require_relative 'message_delivery'
require_relative 'chat_protocol'
require_relative 'heartbeat'
require_relative 'message_dag'

class ChatClient
  include Bud
  import ChatProtocol => :proto
  include Heartbeat
  import MessageDAG => :dag
  #import MessageDelivery => :network

  def initialize(nick="", server="", lifetime=10000, opts={})
    @nick = nick
    @server = server
    @lifetime = lifetime
    super opts
  end

  state do
    table :peers, [:addr] => [:lifetime]
    scratch :sent_messages, [:sender, :nick, :time, :text]
    
    scratch :new_peers, [:addr] => [:lifetime]
    scratch :server_new_peers, [:addr] => []
    scratch :dead_peers, [:addr]

    scratch :die
  end

  bootstrap do
    proto.set_ipport <= [[ip_port]]
    proto.s_request_node_list <= if @server.length > 0 then [[@server, [ip_port]]] else [] end
    stdio <~ proto.set_ipport { |x| ["Me: " + x[0]]}
  end

  bloom :server do
    server_new_peers <= proto.r_request_node_list
    proto.s_node_inform <+ (peers * server_new_peers).pairs { |p, c| [c.addr, p] } # Tell the newly joined peer of all peers
    proto.s_node_inform <+ server_new_peers { |c| [c.addr, [ip_port, @lifetime]] }
    stdio <~ server_new_peers.notin(peers).map { |c| [ "User " + c.addr + " requested peer list" ] }
  end

  bloom :node_connections do
    new_peers <= proto.r_user_connect { |c| c if c.addr != ip_port }
    new_peers <= proto.r_node_inform { |c| c if c.addr != ip_port }
    dead_peers <= proto.r_user_disconnect
    peers <+ new_peers
    peers <- (peers * dead_peers).pairs(:addr => :addr).lefts
    proto.s_user_connect <= proto.r_node_inform { |c| [c.addr, [ip_port, @lifetime]] if c.addr != ip_port }

    proto.s_new_message <= (new_peers * dag.message_store).pairs { |p, m| [p.addr, m] }
    proto.s_new_message_relation <= (new_peers * dag.relations).pairs { |p, r| [p.addr, r] }

    dag.new_messages <= proto.r_new_message
    dag.new_relations <= proto.r_new_message_relation
  end

  bloom :node_input do
    sent_messages <= stdio do |s|
      [ip_port, @nick, time(), s.line] if s.line[0] != "/"
    end

    die <= stdio do |x|
      if x.line[0,5] == "/quit" then
        Thread.new do
          sleep 5.0
          Kernel.exit(0)
        end
        [true]
      end
    end

    proto.s_user_disconnect <= (peers * die).lefts { |p| [p.addr, [ip_port]] }

    dag.in_new <= sent_messages { |x| [x] }

    proto.s_new_message <= (dag.out_messages * peers).pairs do |msg, peer|
      [peer.addr, msg]
    end

    proto.s_new_message_relation <= (dag.out_relations * peers).pairs do |rel, peer|
      [peer.addr, rel]
     end
  end

  bloom :node_stdout do
    stdio <~ proto.r_new_message { |m| [pretty_print(m)] }
    stdio <~ new_peers.notin(peers).map { |u| ["User " + u.addr + " joined"] }
    stdio <~ dead_peers { |u| ["User " + u.addr + " left"] }
    stdio <~ proto.c_user_disconnect { |m| ["[QUIT] Node aware: " + m.rcv] }
  end

  def pretty_print(val)
    return "("+val[0].to_s+") ["+val[2][1]+"]: " + val[2][3]
  end

  def time()
    (Time.now.to_f*1000.0).to_i
  end
end


DEFAULT_ADDR = "127.0.0.1:12345"

if ARGV[0] == "run"
  addr = (ARGV.length >= 3) ? ARGV[2] : DEFAULT_ADDR
  ip, port = addr.split(":")
  server = (ARGV.length >= 4) ? ARGV[3] : DEFAULT_ADDR
  puts "Server address: #{server}"
  program = ChatClient.new(ARGV[1], server, 10000, :ip => ip, :port => port, :stdin => $stdin)
  program.run_fg
end
