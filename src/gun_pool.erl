%% Copyright (c) 2021, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(gun_pool).
-behaviour(gen_statem).

%% Pools.
-export([start_pool/3]).
-export([stop_pool/2]).
-export([stop_pool/3]).
% @todo shutdown pool?
-export([info/1]).
-export([info/2]).
%% @todo -export([get_connection/2]).

%% Requests.
-export([delete/2]).
-export([delete/3]).
-export([get/2]).
-export([get/3]).
-export([head/2]).
-export([head/3]).
-export([options/2]).
-export([options/3]).
-export([patch/2]).
-export([patch/3]).
-export([patch/4]).
-export([post/2]).
-export([post/3]).
-export([post/4]).
-export([put/2]).
-export([put/3]).
-export([put/4]).

%% Generic requests interface.
-export([headers/3]).
-export([headers/4]).
-export([request/4]).
-export([request/5]).

%% Streaming data.
-export([data/3]).

%% Tunneling.
%% @todo -export([connect/2]).
%% @todo -export([connect/3]).
%% @todo -export([connect/4]).

%% Cookies.
%% @todo -export([gc_cookies/1]).
%% @todo -export([session_gc_cookies/1]).

%% Awaiting gun messages.
-export([await/1]).
-export([await/2]).
-export([await/3]).
-export([await_body/1]).
-export([await_body/2]).
-export([await_body/3]).

%% Flushing gun messages.
-export([flush/1]).

%% Streams.
-export([update_flow/2]).
-export([cancel/1]).
-export([stream_info/1]).

%% Websocket.
%% @todo Websocket upgrade would require detaching the connection under some conditions. -export([ws_upgrade/1]).
%% @todo Websocket upgrade would require detaching the connection under some conditions. -export([ws_upgrade/2]).
%% @todo Websocket upgrade would require detaching the connection under some conditions. -export([ws_upgrade/3]).
-export([ws_send/2]).

%% Internals.
-export([callback_mode/0]).
-export([start_link/3]).
-export([init/1]).
-export([degraded/3]).
-export([operational/3]).

%% @todo opts() type

-opaque pool_stream_ref() :: {pid(), gun:stream_ref()}.
-export_type([pool_stream_ref/0]).

-type req_opts() :: #{
	%% Options common with normal Gun.
	flow => pos_integer(),
	reply_to => pid(),
%	@todo tunnel => stream_ref(),

	%% Options specific to pools.
	create_pool_if_missing => boolean(),
	scope => any()
}.
-export_type([req_opts/0]).

-type ws_send_opts() :: #{
	%% @todo authority
	%% @todo Options specific to pools here. like scope
}.
-export_type([ws_send_opts/0]).

%% @todo tunnel
-type meta() :: #{pid() => #{ws => gun:stream_ref()}}.

-record(state, {
	host, %% @todo type
	port, %% @todo type
	opts, %% @todo type
	table :: ets:tid(),
	conns :: #{pid() => down | {setup, any()} | {up, http | http2 | ws | raw, map()}},
	conns_meta = #{} :: meta()
}).

%% Pool management.

%% @todo spec
start_pool(Host, Port, Opts) ->
	supervisor:start_child(gun_pools_sup, [Host, Port, Opts]).

stop_pool(Host, Port) ->
	stop_pool(Host, Port, #{}).

stop_pool(Host, Port, ReqOpts) ->
	supervisor:terminate_child(gun_pools_sup,
		get_pool(iolist_to_binary([Host, $:, integer_to_binary(Port)]), ReqOpts)).

%% @todo spec
info(ManagerPid) when is_pid(ManagerPid) ->
	gen_statem:call(ManagerPid, info);
info(Authority) ->
	info(Authority, default).

%% @todo spec
info(Authority, Scope) ->
	case ets:lookup(gun_pools, {Scope, Authority}) of
		[] ->
			undefined;
		[{_, ManagerPid}] ->
			gen_statem:call(ManagerPid, info)
	end.

%% Requests.

-spec delete(iodata(), gun:req_headers()) -> pool_stream_ref().
delete(Path, Headers) ->
	request(<<"DELETE">>, Path, Headers, <<>>).

-spec delete(iodata(), gun:req_headers(), req_opts()) -> pool_stream_ref().
delete(Path, Headers, ReqOpts) ->
	request(<<"DELETE">>, Path, Headers, <<>>, ReqOpts).

-spec get(iodata(), gun:req_headers()) -> pool_stream_ref().
get(Path, Headers) ->
	request(<<"GET">>, Path, Headers, <<>>).

-spec get(iodata(), gun:req_headers(), req_opts()) -> pool_stream_ref().
get(Path, Headers, ReqOpts) ->
	request(<<"GET">>, Path, Headers, <<>>, ReqOpts).

-spec head(iodata(), gun:req_headers()) -> pool_stream_ref().
head(Path, Headers) ->
	request(<<"HEAD">>, Path, Headers, <<>>).

-spec head(iodata(), gun:req_headers(), req_opts()) -> pool_stream_ref().
head(Path, Headers, ReqOpts) ->
	request(<<"HEAD">>, Path, Headers, <<>>, ReqOpts).

-spec options(iodata(), gun:req_headers()) -> pool_stream_ref().
options(Path, Headers) ->
	request(<<"OPTIONS">>, Path, Headers, <<>>).

-spec options(iodata(), gun:req_headers(), req_opts()) -> pool_stream_ref().
options(Path, Headers, ReqOpts) ->
	request(<<"OPTIONS">>, Path, Headers, <<>>, ReqOpts).

-spec patch(iodata(), gun:req_headers()) -> pool_stream_ref().
patch(Path, Headers) ->
	headers(<<"PATCH">>, Path, Headers).

-spec patch(iodata(), gun:req_headers(), iodata() | req_opts()) -> pool_stream_ref().
patch(Path, Headers, ReqOpts) when is_map(ReqOpts) ->
	headers(<<"PATCH">>, Path, Headers, ReqOpts);
patch(Path, Headers, Body) ->
	request(<<"PATCH">>, Path, Headers, Body).

-spec patch(iodata(), gun:req_headers(), iodata(), req_opts()) -> pool_stream_ref().
patch(Path, Headers, Body, ReqOpts) ->
	request(<<"PATCH">>, Path, Headers, Body, ReqOpts).

-spec post(iodata(), gun:req_headers()) -> pool_stream_ref().
post(Path, Headers) ->
	headers(<<"POST">>, Path, Headers).

-spec post(iodata(), gun:req_headers(), iodata() | req_opts()) -> pool_stream_ref().
post(Path, Headers, ReqOpts) when is_map(ReqOpts) ->
	headers(<<"POST">>, Path, Headers, ReqOpts);
post(Path, Headers, Body) ->
	request(<<"POST">>, Path, Headers, Body).

-spec post(iodata(), gun:req_headers(), iodata(), req_opts()) -> pool_stream_ref().
post(Path, Headers, Body, ReqOpts) ->
	request(<<"POST">>, Path, Headers, Body, ReqOpts).

-spec put(iodata(), gun:req_headers()) -> pool_stream_ref().
put(Path, Headers) ->
	headers(<<"PUT">>, Path, Headers).

-spec put(iodata(), gun:req_headers(), iodata() | req_opts()) -> pool_stream_ref().
put(Path, Headers, ReqOpts) when is_map(ReqOpts) ->
	headers(<<"PUT">>, Path, Headers, ReqOpts);
put(Path, Headers, Body) ->
	request(<<"PUT">>, Path, Headers, Body).

-spec put(iodata(), gun:req_headers(), iodata(), req_opts()) -> pool_stream_ref().
put(Path, Headers, Body, ReqOpts) ->
	request(<<"PUT">>, Path, Headers, Body, ReqOpts).

%% Generic requests interface.
%%
%% @todo Accept a TargetURI map as well as a normal Path.

-spec headers(iodata(), iodata(), gun:req_headers()) -> pool_stream_ref().
headers(Method, Path, Headers) ->
	headers(Method, Path, Headers, #{}).

-spec headers(iodata(), iodata(), gun:req_headers(), req_opts()) -> pool_stream_ref().
headers(Method, Path, Headers, ReqOpts) ->
	case get_pool(authority(Headers), ReqOpts) of
		undefined ->
			error; %% @todo
		ManagerPid ->
			case get_connection(ManagerPid, ReqOpts) of
				undefined ->
					error; %% @todo
				{ConnPid, _Meta} ->
					StreamRef = gun:headers(ConnPid, Method, Path, Headers, ReqOpts),
					%% @todo Synchronous mode.
					{ConnPid, StreamRef}
			end
	end.

-spec request(iodata(), iodata(), gun:req_headers(), iodata()) -> pool_stream_ref().
request(Method, Path, Headers, Body) ->
	request(Method, Path, Headers, Body, #{}).

-spec request(iodata(), iodata(), gun:req_headers(), iodata(), req_opts()) -> pool_stream_ref().
request(Method, Path, Headers, Body, ReqOpts) ->
	case get_pool(authority(Headers), ReqOpts) of
		undefined ->
			error; %% @todo
		ManagerPid ->
			case get_connection(ManagerPid, ReqOpts) of
				undefined ->
					error; %% @todo
				{ConnPid, _Meta} ->
					StreamRef = gun:request(ConnPid, Method, Path, Headers, Body, ReqOpts),
					%% @todo Synchronous mode.
					{ConnPid, StreamRef}
			end
	end.

%% We require the host to be given in the headers for the time being.
%% @todo Allow passing it in options.
authority(#{<<"host">> := Authority}) ->
	Authority;
authority(Headers) ->
	{_, Authority} = lists:keyfind(<<"host">>, 1, Headers),
	Authority.

get_pool(Authority0, ReqOpts) ->
	Authority = iolist_to_binary(Authority0),
	CreatePoolIfMissing = maps:get(create_pool_if_missing, ReqOpts, false),
	Scope = maps:get(scope, ReqOpts, default),
	case ets:lookup(gun_pools, {Scope, Authority}) of
		[] when CreatePoolIfMissing ->
			create_pool(Authority, ReqOpts);
		[] ->
			undefined;
		[{_, ManagerPid}] ->
			ManagerPid
	end.

create_pool(_Host, _ReqOpts) ->
	%% @todo Dynamic pools will not automatically reconnect if there's no incoming requests.
	undefined.

-spec get_connection(pid(), req_opts()) -> undefined | {pid(), map()}.
get_connection(ManagerPid, ReqOpts) ->
	gen_server:call(ManagerPid, {?FUNCTION_NAME, ReqOpts}).

%% Streaming data.

-spec data(pool_stream_ref(), fin | nofin, iodata()) -> ok.
data({ConnPid, StreamRef}, IsFin, Data) ->
	gun:data(ConnPid, StreamRef, IsFin, Data).

%% Awaiting gun messages.

-spec await(pool_stream_ref()) -> gun:await_result().
await({ConnPid, StreamRef}) ->
	gun:await(ConnPid, StreamRef).

-spec await(pool_stream_ref(), timeout() | reference()) -> gun:await_result().
await({ConnPid, StreamRef}, MRefOrTimeout) ->
	gun:await(ConnPid, StreamRef, MRefOrTimeout).

-spec await(pool_stream_ref(), timeout(), reference()) -> gun:await_result().
await({ConnPid, StreamRef}, Timeout, MRef) ->
	gun:await(ConnPid, StreamRef, Timeout, MRef).

-spec await_body(pool_stream_ref()) -> gun:await_body_result().
await_body({ConnPid, StreamRef}) ->
	gun:await_body(ConnPid, StreamRef).

-spec await_body(pool_stream_ref(), timeout() | reference()) -> gun:await_body_result().
await_body({ConnPid, StreamRef}, MRefOrTimeout) ->
	gun:await_body(ConnPid, StreamRef, MRefOrTimeout).

-spec await_body(pool_stream_ref(), timeout(), reference()) -> gun:await_body_result().
await_body({ConnPid, StreamRef}, Timeout, MRef) ->
	gun:await_body(ConnPid, StreamRef, Timeout, MRef).

%% Flushing gun messages.

-spec flush(pool_stream_ref()) -> ok.
flush({ConnPid, _}) ->
	gun:flush(ConnPid).

%% Flow control.

-spec update_flow(pool_stream_ref(), pos_integer()) -> ok.
update_flow({ConnPid, StreamRef}, Flow) ->
	gun:update_flow(ConnPid, StreamRef, Flow).

%% Cancelling a stream.

-spec cancel(pool_stream_ref()) -> ok.
cancel({ConnPid, StreamRef}) ->
	gun:cancel(ConnPid, StreamRef).

%% Information about a stream.

-spec stream_info(pool_stream_ref()) -> {ok, map() | undefined} | {error, not_connected}.
stream_info({ConnPid, StreamRef}) ->
	gun:stream_info(ConnPid, StreamRef).

%% Websocket.

-spec ws_send(gun:ws_frame() | [gun:ws_frame()], ws_send_opts()) -> ok.
ws_send(Frames, WsSendOpts=#{authority := Authority}) ->
	case get_pool(Authority, WsSendOpts) of
		undefined ->
			error; %% @todo
		ManagerPid ->
			case get_connection(ManagerPid, WsSendOpts) of
				undefined ->
					error; %% @todo
				{ConnPid, #{ws := StreamRef}} ->
					gun:ws_send(ConnPid, StreamRef, Frames)
			end
	end.

%% Pool manager internals.
%%
%% The pool manager is responsible for starting connection processes
%% and restarting them as necessary. It also provides a suitable
%% connection process to any caller that needs it.
%%
%% The pool manager installs an event handler into each connection.
%% The event handler is responsible for counting the number of
%% active streams. It updates the gun_pooled_conns ets table
%% whenever a stream begins or ends.
%%
%% A connection is deemed suitable if it is possible to open new
%% streams. How many streams can be open at any one time depends
%% on the protocol. For HTTP/2 the manager process keeps track of
%% the connection's settings to know the maximum. For non-stream
%% based protocols, there is no limit.
%%
%% The connection to be used is otherwise chosen randomly. The
%% first connection that is suitable is returned. There is no
%% need to "give back" the connection to the manager.

%% @todo
%% What should happen if we always fail to reconnect? I suspect we keep the manager
%% around and propagate errors, the same as if there's no more capacity? Perhaps have alarms?
%%
%% @todo
%% Dynamic pools will open connections as necessary and keep unused connections closed.
%% Dynamic pools should probably shutdown after some time when they're no longer used.
%%
%% @todo
%% We may want to have both sync and async modes of doing requests, not just async.

callback_mode() -> state_functions.

start_link(Host, Port, Opts) ->
	gen_statem:start_link(?MODULE, {Host, Port, Opts}, []).

%% @todo Probably don't mix Gun and pool options. Have Gun Opts in a pool option.
init({Host, Port, Opts}) ->
	Transport = maps:get(transport, Opts, default_transport(Port)),
	Authority = gun_http:host_header(Transport, Host, Port),
	Scope = maps:get(scope, Opts, default),
	true = ets:insert_new(gun_pools, {{Scope, iolist_to_binary(Authority)}, self()}),
	Tid = ets:new(gun_pooled_conns, [ordered_set, public]),
	Size = maps:get(size, Opts, 8),
	%% @todo Only start processes in static mode.
	ConnOpts = conn_opts(Tid, Opts),
	Conns = maps:from_list([begin
		{ok, ConnPid} = gun:open(Host, Port, ConnOpts),
		_ = monitor(process, ConnPid),
		{ConnPid, down}
	end || _ <- lists:seq(1, Size)]),
	State = #state{
		host=Host,
		port=Port,
		opts=Opts,
		table=Tid,
		conns=Conns
	},
	{ok, degraded, State}.

default_transport(443) -> gun_tls;
default_transport(_) -> gun_tcp.

conn_opts(Tid, Opts0) ->
	EventHandlerState = maps:with([event_handler], Opts0),
	H2Opts = maps:get(http2_opts, Opts0, #{}),
	Opts = Opts0#{
		event_handler => {gun_pool_events_h, EventHandlerState#{
			table => Tid
		}},
		http2_opts => H2Opts#{
			notify_settings_changed => true
		}
	},
	maps:without([scope, setup_fun, size], Opts).

%% We use the degraded state as long as at least one connection is degraded.
%% @todo Probably count degraded connections separately to avoid counting every time.
degraded(info, Msg={gun_up, ConnPid, _}, StateData=#state{opts=Opts, conns=Conns}) ->
	#{ConnPid := down} = Conns,
	%% We optionally run the setup function if one is defined. The
	%% setup function tells us whether we are fully up or not. The
	%% setup function may be called repeatedly until the connection
	%% is established.
	%%
	%% @todo It is possible that the connection never does get
	%% fully established. We should deal with this. We probably
	%% need to handle all messages.
	{SetupFun, SetupState0} = setup_fun(Opts),
	degraded_setup(ConnPid, Msg, StateData, SetupFun, SetupState0);
%% @todo
%degraded(info, Msg={gun_tunnel_up, ConnPid, _, _}, StateData0=#state{conns=Conns}) ->
%	;
degraded(info, Msg={gun_upgrade, ConnPid, _, _, _},
		StateData=#state{opts=#{setup_fun := {SetupFun, _}}, conns=Conns}) ->
	%% @todo Probably shouldn't crash if the state is incorrect, that's programmer error though.
	#{ConnPid := {setup, SetupState0}} = Conns,
	%% We run the setup function again using the state previously kept.
	%% @todo We need to keep track of the StreamRef for Websocket I guess?
	degraded_setup(ConnPid, Msg, StateData, SetupFun, SetupState0);
degraded(Type, Event, StateData) ->
	handle_common(Type, Event, ?FUNCTION_NAME, StateData).

setup_fun(#{setup_fun := SetupFun}) ->
	SetupFun;
setup_fun(_) ->
	{fun (_, {gun_up, _, Protocol}, _) ->
		{up, Protocol, #{}}
	end, undefined}.

degraded_setup(ConnPid, Msg, StateData0=#state{conns=Conns, conns_meta=ConnsMeta}, SetupFun, SetupState0) ->
	case SetupFun(ConnPid, Msg, SetupState0) of
		Setup={setup, _SetupState} ->
			StateData = StateData0#state{conns=Conns#{ConnPid => Setup}},
			{keep_state, StateData};
		%% The Meta is different from Settings. It allows passing around
		%% Websocket or tunnel stream refs.
		{up, Protocol, Meta} ->
			Settings = #{},
			StateData = StateData0#state{
				conns=Conns#{ConnPid => {up, Protocol, Settings}},
				conns_meta=ConnsMeta#{ConnPid => Meta}
			},
			case is_degraded(StateData) of
				true -> {keep_state, StateData};
				false -> {next_state, operational, StateData}
			end
	end.

is_degraded(#state{conns=Conns0}) ->
	Conns = maps:to_list(Conns0),
	Len = length(Conns),
	Ups = [up || {_, {up, _, _}} <- Conns],
	Len =/= length(Ups).

operational(Type, Event, StateData) ->
	handle_common(Type, Event, ?FUNCTION_NAME, StateData).

handle_common({call, From}, {get_connection, _ReqOpts}, _,
		StateData=#state{conns_meta=ConnsMeta}) ->
	case find_available_connection(StateData) of
		none ->
			{keep_state_and_data, {reply, From, undefined}};
		ConnPid ->
			Meta = maps:get(ConnPid, ConnsMeta, #{}),
			{keep_state_and_data, {reply, From, {ConnPid, Meta}}}
	end;
handle_common(info, {gun_notify, ConnPid, settings_changed, Settings}, _, StateData=#state{conns=Conns}) ->
	%% Assert that the state is correct.
	{up, http2, _} = maps:get(ConnPid, Conns),
	{keep_state, StateData#state{conns=Conns#{ConnPid => {up, http2, Settings}}}};
handle_common(info, {gun_down, ConnPid, Protocol, _Reason, _KilledStreams}, _, StateData=#state{conns=Conns}) ->
	{up, Protocol, _} = maps:get(ConnPid, Conns),
	{next_state, degraded, StateData#state{conns=Conns#{ConnPid => down}}};
%% @todo We do not want to reconnect automatically when the pool is dynamic.
handle_common(info, {'DOWN', _MRef, process, ConnPid0, _Reason}, _,
		StateData=#state{host=Host, port=Port, opts=Opts, table=Tid, conns=Conns0, conns_meta=ConnsMeta0}) ->
	Conns = maps:remove(ConnPid0, Conns0),
	ConnsMeta = maps:remove(ConnPid0, ConnsMeta0),
	ConnOpts = conn_opts(Tid, Opts),
	{ok, ConnPid} = gun:open(Host, Port, ConnOpts),
	_ = monitor(process, ConnPid),
	{next_state, degraded, StateData#state{conns=Conns#{ConnPid => down}, conns_meta=ConnsMeta}};
handle_common({call, From}, info, StateName, #state{host=Host, port=Port,
		opts=Opts, table=Tid, conns=Conns, conns_meta=ConnsMeta}) ->
	{keep_state_and_data, {reply, From, {StateName, #{
		%% @todo Not sure whether all of this should be documented. Maybe not ConnsMeta for now?
		host => Host,
		port => Port,
		opts => Opts,
		table => Tid,
		conns => Conns,
		conns_meta => ConnsMeta
	}}}};
handle_common(Type, Event, StateName, StateData) ->
	logger:error("Unexpected event in state ~p of type ~p:~n~w~n~p~n",
		[StateName, Type, Event, StateData]),
	keep_state_and_data.

%% We go over every connection and return the first one
%% we find that has capacity. How we determine whether
%% capacity is available depends on the protocol. For
%% HTTP/2 we look into the protocol settings. The
%% current number of streams is maintained by the
%% event handler gun_pool_events_h.
find_available_connection(#state{table=Tid, conns=Conns}) ->
	I = lists:sort([{rand:uniform(), K} || K <- maps:keys(Conns)]),
	find_available_connection(I, Conns, Tid).

find_available_connection([], _, _) ->
	none;
find_available_connection([{_, ConnPid}|I], Conns, Tid) ->
	case maps:get(ConnPid, Conns) of
		{up, Protocol, Settings} ->
			MaxStreams = max_streams(Protocol, Settings),
			CurrentStreams = case ets:lookup(Tid, ConnPid) of
				[] ->
					0;
				[{_, CS}] ->
					CS
			end,
			if
				CurrentStreams + 1 > MaxStreams ->
					find_available_connection(I, Conns, Tid);
				true ->
					ConnPid
			end;
		_ ->
			find_available_connection(I, Conns, Tid)
	end.

max_streams(http, _) ->
	1;
max_streams(http2, #{max_concurrent_streams := MaxStreams}) ->
	MaxStreams;
max_streams(http2, #{}) ->
	infinity;
%% There are no streams or Gun is not aware of streams when
%% the protocol is Websocket or raw.
max_streams(ws, _) ->
	infinity;
max_streams(raw, _) ->
	infinity.
