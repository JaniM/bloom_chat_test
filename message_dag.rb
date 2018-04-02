
module MessageDAG
  state do
    table :message_store, [:id] => [:timestamp, :data] # Stores all events known of
    table :relations, [:id, :target] => [] # Stores DAG node relations
    table :leaves, [:id] => [] # Messages that have no children
    table :extremities, [:id] => [] # Messages that have zero parents and don't connect to the main graph
    table :linearized, [:id] => [:number, :timestamp, :data] # Linearized message queue - can be used without other lookups
    table :unlinearized, [:id] # Messages that haven't been linearized yet

    lmax :seqlin # Number to be used for new linearized messages

    scratch :unldepth, [:id] => [:depth] # Depth of unlinearized messages
    scratch :unleligible, [:id, :parent] => [:depth] # Messages eligible for linearization
    scratch :unlinearizable, [:id] => [] # Messages ineligible for linearization
    scratch :unlparents, [:id, :parent] => [:depth] # All parents of unlinearized messages

    interface input, :new_messages, [:id] => [:timestamp, :data] # Messages to be inserted to the DAG
    interface input, :new_relations, [:id, :target] => [] # Relations to be inserted to the DAG
    interface input, :in_new, [:data] # Messages to be appended
    interface output, :out_messages, [:id] => [:timestamp, :data]
    interface output, :out_relations, [:id, :target] => []
  end

  bootstrap do
    seqlin <= 0

    # test
    # new_messages <= [[0, 0, [0,0,0,"asd"]]]
    # new_messages <= [[1, 1, [0,0,0,"hello"]]]
    # new_messages <= [[2, 1, [0,0,0,"hiya"]]]
    # new_messages <= [[3, 1, [0,0,0,"third leaf"]]]
    # new_messages <= [[31, 1, [0,0,0,"fourth leaf"]]]
    # new_messages <= [[4, 2, [0,0,0,"works?"]]]
    # new_messages <= [[5, 3, [0,0,0,"yup"]]]
    # new_relations <= [[0, -1]]
    # new_relations <= [[1, 0]]
    # new_relations <= [[2, 0]]
    # new_relations <= [[3, 0]]
    # new_relations <= [[31, 0]]
    # new_relations <= [[4, 1]]
    # new_relations <= [[4, 2]]
    # new_relations <= [[5, 4]]
  end

  bloom :insert do
    message_store <= new_messages
    leaves <= new_messages.notin(relations, :id => :target).map { |x| [x.id] }
    extremities <= new_messages.notin(relations, :id => :id).map { |x| [x.id] }

    relations <= new_relations
    #stdio <~ new_messages{ |x| ["new_messages: " + x.to_s] }
    #stdio <~ new_relations { |x| ["new_relations : " + x.to_s] }
  end

  bloom :interface do
    out_messages <= in_new { |m| [time().to_s+"@"+m[0][0], time(), m[0]] }
    #stdio <~ out_messages { |x| ["out_messages : " + x.to_s] }
    new_messages <+ out_messages
    temp :in_new_relations <= (out_messages * leaves).pairs { |x, l| [x.id, l.id] }
    new_relations <+ in_new_relations
    out_relations <= in_new_relations
  end

  bloom :unextremify do
    leaves <- (leaves * new_relations).pairs(:id => :target).lefts
    extremities <- (extremities * new_relations).pairs(:id => :id).lefts
  end

  # bloom :linearize do
  #   # BUG: does not ensure that new messages can't anymore be inserted
  #   unlinearized <= new_messages{ |x| [x.id] }

  #   # Figure out _all_ parent nodes for non-extremities
  #   unleligible <= unlinearized.notin(extremities, :id => :id).map { |u| [u.id, u.id, 0] }
  #   unleligible <= unlparents.notin(extremities, :parent => :id)
  #   unlinearizable <= (unlparents * extremities).pairs(:parent => :id) { |x, y| [x.id] }
  #   unlparents <= (unleligible * relations).pairs(:parent => :id) { |u, r| [u.id, r.target, u.depth + 1] if r.target != -1 }

  #   unldepth <= unleligible.notin(unlinearizable, :id => :id).group([:id], max(:depth))
  #   linearized <= (unldepth * message_store).combos(unldepth.id => message_store.id) do |d, m|
  #     [m.id, d.depth, m.timestamp, m.data]
  #   end
  #   unlinearized <- (unlinearized * unldepth).pairs(:id => :id).lefts

  #   stdio <~ unldepth { |x| ["unldepth : " + x.to_s] }
  #   stdio <~ unlparents { |x| ["unlparents : " + x.to_s] }
  #   stdio <~ linearized { |x| ["linearized : " + x.to_s] }
  # end

  def time()
    (Time.now.to_f*1000.0).to_i
  end
end