%%% @author Niclas Axelsson <niclas@burbas.se>
%%% @doc
%%% Nova supervisor
%%% @end

-module(nova_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-include("include/nova.hrl").
-include("nova.hrl").

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    %% This is a bit ugly, but we need to do this anyhow(?)
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},

    Configuration = application:get_env(nova, cowboy_configuration, #{}),

    setup_cowboy(Configuration),

    SessionManager = application:get_env(nova, session_manager, nova_session_ets),

    Children = [
                child(nova_handlers, nova_handlers),
                child(nova_plugin, nova_plugin),
                child(SessionManager, SessionManager),
                child(nova_cache_sup, supervisor, nova_cache_sup),
                child(nova_watcher, nova_watcher)
               ],

    case application:get_env(nova, dev_mode, false) of
        false ->
            ?INFO("Starting nova in production mode...");
        true ->
            ?INFO("Starting nova in developer mode...")
    end,

    {ok, {SupFlags, Children}}.




%%%===================================================================
%%% Internal functions
%%%===================================================================
child(Id, Type, Mod, Args) ->
    #{id => Id,
      start => {Mod, start_link, Args},
      restart => permanent,
      shutdown => 5000,
      type => Type,
      modules => [Mod]}.

child(Id, Type, Mod) ->
    child(Id, Type, Mod, []).

child(Id, Mod) ->
    child(Id, worker, Mod).

setup_cowboy(Configuration) ->
    case start_cowboy(Configuration) of
        {ok, _} ->
            ok;
        {error, Error} ->
            ?ERROR("Cowboy could not start reason: ~p", [Error])
    end.

start_cowboy(Configuration) ->
    ?INFO("Nova is starting cowboy..."),
    Middlewares = maps:get(middlewares, Configuration, [nova_router, nova_handler]),
    StreamHandlers = maps:get(stream_handlers, Configuration, [nova_stream_h, cowboy_compress_h, cowboy_stream_h]),
    Options = maps:get(options, Configuration, #{compress => true}),

    %% Build the options map
    CowboyOptions1 = Options#{middlewares => Middlewares,
                              stream_handlers => StreamHandlers},

    %% Compile the routes
    Dispatch =
        case application:get_env(nova, bootstrap_application, undefined) of
            undefined ->
                ?ERROR("You do not have a main nova application defined. Add the following in your sys.config-file:~n{nova, [~n  {bootstrap_application, your_application}~n..."),
                throw({error, no_nova_app_defined});
            App ->
                nova_router:compile([App])
        end,

    CowboyOptions2 = CowboyOptions1#{env => #{dispatch => Dispatch}},

    case maps:get(use_ssl, Configuration, false) of
        false ->
            cowboy:start_clear(
              ?NOVA_LISTENER,
              [{port, maps:get(port, Configuration, ?NOVA_STD_PORT)}],
              CowboyOptions2);
        _ ->
            CACert = maps:get(ca_cert, Configuration),
            Cert = maps:get(cert, Configuration),
            Port = maps:get(ssl_port, Configuration, ?NOVA_STD_SSL_PORT),
            ?INFO("Nova is starting SSL on port ~p", [Port]),
            cowboy:start_tls(
              ?NOVA_LISTENER, [
                               {port, Port},
                               {certfile, Cert},
                               {cacertfile, CACert}
                              ],
              CowboyOptions2)
    end.
