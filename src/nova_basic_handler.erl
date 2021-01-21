-module(nova_basic_handler).

-export([handle_json/3,
         handle_ok/3,
         handle_status/3,
         handle_redirect/3,
         handle_sendfile/3]).

-include_lib("nova/include/nova.hrl").

-type mod_fun() :: {Module :: atom(),
                    Function :: atom()} |
                   undefined.

-type erlydtl_vars() :: map() |
                        [{Key :: atom() | binary() | string(), Value :: any()}].

%%--------------------------------------------------------------------
%% @doc
%% Handler for JSON. It takes two different return objects:
%%
%% <options>
%%   <option for="{json, JSON :: map()}"> returns the JSON encoded to the user.
%%     If the operation was a POST the HTTP-status code will be 201, otherwise
%%     200.</option>
%%
%%   <option for="{json, StatusCode :: integer(), Headers :: map(), JSON :: map()}"> Same
%%     operation as the above except you can set custom status code and custom
%%     headers.</option>
%% </options>
%% @end
%%--------------------------------------------------------------------
-spec handle_json({json, JSON :: map()} |
                  {json, StatusCode :: integer(), Headers :: map(),
                   JSON :: map()},
                  ModFun :: mod_fun(),
                  State ::
                      nova_http_handler:nova_http_state()) -> nova_handlers:handler_return() |
                                                              no_return().

handle_json({json, StatusCode, Headers, JSON}, _ModFun,
            State) ->
    try json:encode(JSON, [binary, maps]) of
        EncodedJSON ->
            Headers0 = maps:merge(#{<<"content-type">> =>
                                        <<"application/json">>},
                                  Headers),
            {ok, StatusCode, Headers0, EncodedJSON, State}
    catch
        Type:Reason:Stacktrace ->
            ?ERROR("Error while processing JSON. Type: ~p "
                   "Reason: ~p Stacktrace: ~p",
                   [Type, Reason, Stacktrace]),
            handle_status({status, 500}, undefined, State)
    end;
handle_json({json, JSON}, ModFun,
            State = #{req := #{method := Method}}) ->
    case Method of
        <<"POST">> ->
            handle_json({json, 201, #{}, JSON}, ModFun, State);
        _ -> handle_json({json, 200, #{}, JSON}, ModFun, State)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Handler for regular views. This will render a template with given variables.
%% If not another view is specified in options a view that corresponds to the controller will be
%% rendered.
%%
%% <code title="Example of controller named 'app_main_controller.erl'">
%% -module(my_first_controller).
%% -compile(export_all).
%%
%% my_function(_Req) ->
%%    {ok, []}.
%% </code>
%% The example above will then render the view named <icode>'app_main.dtl'</icode>
%%
%% Options can be specified as follows:
%%
%% - <icode>view</icode> - Specifies if another view should be rendered instead of default one
%%
%% - <icode>headers</icode> - Custom headers
%% @end
%%--------------------------------------------------------------------
-spec handle_ok({ok, Variables :: erlydtl_vars()} |
                {ok, Variables :: erlydtl_vars(), Options :: map()},
                ModFun :: mod_fun(),
                State ::
                    nova_http_handler:nova_http_state()) -> nova_handlers:handler_return() |
                                                            no_return().

handle_ok({ok, Variables}, {Mod, _Func}, State) ->
    %% Derive the view from module
    ViewNameAtom = get_view_name(Mod),
    handle_view(ViewNameAtom, Variables, #{}, State);
handle_ok({ok, Variables, Options}, {Mod, _Func},
          State) ->
    View = case maps:get(view, Options, undefined) of
               undefined ->
                   ViewName = atom_to_list(Mod) ++ "_dtl",
                   list_to_atom(ViewName);
               CustomView when is_atom(CustomView) ->
                   ViewName = atom_to_list(CustomView) ++ "_dtl",
                   list_to_atom(ViewName);
               CustomView -> list_to_atom(CustomView ++ "_dtl")
           end,
    handle_view(View, Variables, Options, State).

%%--------------------------------------------------------------------
%% @doc
%% Handler for returning http status codes. There's three different ways one can
%% return status code. The most basic case is <icode>{status, Status}</icode> where Status is
%% the code that should be returned.
%%
%% If there's a need for additional headers to be sent along with the http code one can specify
%% a third argument that is a map with header-fields.
%%
%% One can also send in a body as a fourth argument in the tuple. It can either be a binary or
%% a map. If it's a map it will be concidered a JSON-structure and encoded.
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_status({status, StatusCode :: integer()} |
                    {status, StatusCode :: integer(),
                     ExtraHeaders :: map()} |
                    {status, StatusCode :: integer(), ExtraHeaders :: map(),
                     Body :: binary() | map()},
                    ModFun :: mod_fun(),
                    State ::
                        nova_http_handler:nova_http_state()) -> nova_handlers:handler_return().

handle_status({status, Status, ExtraHeaders, JSON},
              _ModFun, State)
    when is_map(JSON) ->
    %% We do not need to render a status page since we just return a JSON structure
    Headers0 = maps:merge(#{<<"content-type">> =>
                                <<"application/json">>},
                          ExtraHeaders),
    {ok,
     Status,
     Headers0,
     json:encode(JSON, [binary]),
     State};
handle_status({status, Status, ExtraHeaders, Body},
              _ModFun, State)
    when is_binary(Body) ->
    %% Body is a binary - just send it out
    {ok, Status, ExtraHeaders, Body, State};
handle_status({status, Status, ExtraHeaders}, _ModFun,
              State = #{req := Req}) ->
    case nova_router:status_page(Status, Req) of
        {ok, _StatusCode, StatusHeaders, StatusBody, _} ->
            Headers0 = maps:merge(ExtraHeaders, StatusHeaders),
            {ok, Status, Headers0, StatusBody, State};
        {error, not_found} ->
            {ok, Status, ExtraHeaders, <<>>, State}
    end;
handle_status({status, Status}, ModFun, State) ->
    handle_status({status, Status, #{}}, ModFun, State).

%%--------------------------------------------------------------------
%% @doc
%% Handles redirects. This will return a 302-status code with a location given
%% by the user. Something like <icode>{redirect, "/login"}</icode> will send a
%% 302 with <icode>location</icode> set to <icode>"/login"</icode>
%% @end
%%-----------------------------------------------------------------
-spec handle_redirect({redirect, Route :: list()},
                      ModFun :: mod_fun(),
                      State ::
                          nova_http_handler:nova_http_state()) -> nova_handlers:handler_return().

handle_redirect({redirect, Route}, _ModFun, State) ->
    Headers = #{<<"Location">> => list_to_binary(Route)},
    {ok, 302, Headers, <<>>, State}.

%%--------------------------------------------------------------------
%% @doc
%% Handles sendfile.
%% @end
%%-----------------------------------------------------------------
-spec handle_sendfile({sendfile,
                       StatusCode :: integer(), Headers :: map(),
                       {Offset :: integer(), Length :: integer(),
                        Path :: list()},
                       Mime :: binary()},
                      ModFun :: mod_fun(),
                      State ::
                          nova_http_handler:nova_http_state()) -> nova_handlers:handler_return() |
                                                                  no_return().

handle_sendfile({sendfile,
                 StatusCode,
                 Headers,
                 {Offset, Length, Path},
                 Mime},
                _ModFun, State) ->
    Headers0 = maps:merge(#{<<"content-type">> => Mime},
                          Headers),
    {ok,
     StatusCode,
     Headers0,
     {sendfile, Offset, Length, Path},
     State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_view(View, Variables, Options, State) ->
    {ok, HTML} = render_dtl(View, Variables, []),
    Headers = case maps:get(headers, Options, undefined) of
                  undefined -> #{<<"content-type">> => <<"text/html">>};
                  UserHeaders -> UserHeaders
              end,
    StatusCode = maps:get(status_code, Options, 200),
    {ok, StatusCode, Headers, HTML, State}.

render_dtl(View, Variables, Options) ->
    case code:is_loaded(View) of
        false ->
            case code:load_file(View) of
                {error, Reason} ->
                    %% Cast a warning since the module could not be found
                    ?ERROR("Could not render ~p. Reason given: ~p",
                           [View, Reason]),
                    throw({error, template_not_found});
                _ -> View:render(Variables, Options)
            end;
        _ -> View:render(Variables, Options)
    end.

get_view_name(Mod) when is_atom(Mod) ->
    StrName = get_view_name(erlang:atom_to_list(Mod)),
    erlang:list_to_atom(StrName);
get_view_name([$_,
               $c,
               $o,
               $n,
               $t,
               $r,
               $o,
               $l,
               $l,
               $e,
               $r]) ->
    "_dtl";
get_view_name([H | T]) -> [H | get_view_name(T)].
