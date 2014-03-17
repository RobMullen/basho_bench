-module(basho_bench_driver_rtevent).

-export([new/1, run/4]).
-export([rand_op/1, rand_key/1]).

-record(state, {
    subscriptions = [],
    max_subscriptions = 50,
    uid,
    host = <<"localhost">>,
    http = <<"http://localhost:80">>,
    nodes = []
}).

new(_) ->
    Uid = list_to_binary(integer_to_list(crypto:rand_uniform(1, 100000))),
    maybe_init_node(),
    Nodes = queue:from_list(basho_bench_config:get(nodes)),
    State = #state{ uid = Uid, nodes = Nodes },
    {ok, State}.

run(request, KeyGen, ValueGen, State) ->
    RequestType = element(KeyGen(), request_types()),
    {Req, NewState} = request(RequestType, ValueGen, State),
    {ok, send(Req, NewState)}.
    
send([], _) ->
    ok;
send(Msg, State = #state{ nodes = Nodes }) ->
    {{value, Node}, Q} = queue:out(Nodes),
    NewNodes = queue:in(Node, Q),
    {listener, Node} ! {self(), Msg},
    State#state{ nodes = NewNodes }.

request(add_timer, ValueGen, State = #state{ uid = Uid, host = Host, http = HTTP }) ->
    <<RTime:8/integer, _/binary>> = Bin = ValueGen(),
    Type = choose_from(Bin, [<<"perm">>, <<"temp">>]),
    {A, B, _} = os:timestamp(),
    Time = A * 1000000 + B + RTime rem 10,
    {{request, 'CREATE', Time, Host, Uid, Bin, HTTP, Type}, State};
request(subscribe, ValueGen, State = #state{ uid = Uid, host = Host }) ->
    Bin = ValueGen(),
    Type = choose_from(Bin, [<<"perm">>, <<"temp">>]),
    Subscriptions = State#state.subscriptions,
    NewState = State#state{ subscriptions = [Bin | Subscriptions] },
    {{request, 'PUBSUB', 0, Host, [], [Bin], [Uid], Type}, NewState};
request(publish, _ValueGen, S = #state{ subscriptions = [] }) ->
    {[], S};
request(publish, ValueGen, State = #state{ host = Host, subscriptions = Subscriptions }) ->
    Bin = ValueGen(),
    Channel = choose_from(Bin, Subscriptions),
    {{request, 'PUBLISH', 0, Host, Channel, Bin, [], Bin}, State};
request(_, _, S) ->
    {[], S}.

maybe_init_node() ->
    Node = basho_bench_config:get(bench_node_name),
    Cookie = basho_bench_config:get(cookie),
    case node() of
        Node ->
            ok;
        _ ->
            net_kernel:start(Node),
            erlang:set_cookie(node(), Cookie)
    end.

request_types() ->
    {add_timer, subscribe, publish, del_timer, unsubscribe, 'SEND', 'SET'}.

rand_op(_) ->
    fun() -> crypto:rand_uniform(1, 4) end.

rand_key(_) ->
    fun() -> list_to_binary(integer_to_list(crypto:rand_uniform(10000, 20000))) end.

choose_from(Bin, Opts) ->
    <<A:16/integer, _/binary>> = Bin,
    lists:nth(A rem length(Opts) + 1, Opts).
