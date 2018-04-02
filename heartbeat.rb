
module Heartbeat
  import ChatProtocol => :proto

  state do
    periodic :heartbeat_timer, 5.0
    table :heartbeats, [:addr] => [:time, :isactive]
    scratch :new_heartbeats, [:addr] => [:time, :isactive]
    scratch :cleared_heartbeats, [:addr] => [:time, :isactive]
  end

  bloom :heartbeating do
    cleared_heartbeats <= new_peers { |u| [u.addr, 0, false] }
    cleared_heartbeats <= (heartbeats * proto.c_heartbeat).pairs(:addr => :rcv).lefts { |u| [u.addr, 0, false] }

    new_heartbeats <= (heartbeats * heartbeat_timer).lefts { |h| [h.addr, time, true] if !h.isactive }

    dead_peers <= (heartbeat_timer * heartbeats * peers).combos(heartbeats.addr => peers.addr) do |_, m, p|
      [m.addr] if m.isactive && time >= m.time + p.lifetime
    end

    # Fill in new state
    heartbeats <+- cleared_heartbeats
    heartbeats <+- new_heartbeats
    heartbeats <- (dead_peers * heartbeats).pairs(:addr => :addr).rights

    proto.s_heartbeat <= new_heartbeats { |x| [x.addr] }
  end
end