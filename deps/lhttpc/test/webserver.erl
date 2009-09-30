%%% ----------------------------------------------------------------------------
%%% Copyright (c) 2009, Erlang Training and Consulting Ltd.
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%    * Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    * Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%    * Neither the name of Erlang Training and Consulting Ltd. nor the
%%%      names of its contributors may be used to endorse or promote products
%%%      derived from this software without specific prior written permission.
%%% 
%%% THIS SOFTWARE IS PROVIDED BY Erlang Training and Consulting Ltd. ''AS IS''
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL Erlang Training and Consulting Ltd. BE
%%% LIABLE SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
%%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
%%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
%%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%% ----------------------------------------------------------------------------

%%% @author Oscar Hellström <oscar@erlang-consulting.com>
%%% @author Magnus Henoch <magnus@erlang-consulting.com>
%%% @doc Simple web server for testing purposes
%%% @end
-module(webserver).

-export([start/2]).
-export([accept_connection/4]).

start(Module, Responders) ->
    LS = listen(Module),
    spawn_link(?MODULE, accept_connection, [self(), Module, LS, Responders]),
    port(Module, LS).

accept_connection(Parent, Module, ListenSocket, Responders) ->
    Socket = accept(Module, ListenSocket),
    server_loop(Module, Socket, nil, [], Responders),
    unlink(Parent).

server_loop(Module, Socket, _, _, []) ->
    Module:close(Socket);
server_loop(Module, Socket, Request, Headers, Responders) ->
    case Module:recv(Socket, 0) of
        {ok, {http_request, _, _, _} = NewRequest} ->
            server_loop(Module, Socket, NewRequest, Headers, Responders);
        {ok, {http_header, _, Field, _, Value}} ->
            NewHeaders = [{Field, Value} | Headers],
            server_loop(Module, Socket, Request, NewHeaders, Responders);
        {ok, http_eoh} ->
            RequestBody = case proplists:get_value('Content-Length', Headers) of
                undefined ->
                    <<>>;
                "0" ->
                    <<>>;
                SLength ->
                    Length = list_to_integer(SLength),
                    setopts(Module, Socket, [{packet, raw}]),
                    {ok, Body} = Module:recv(Socket, Length),
                    setopts(Module, Socket, [{packet, http}]),
                    Body
            end,
            Responder = hd(Responders),
            Responder(Module, Socket, Request, Headers, RequestBody),
            server_loop(Module, Socket, none, [], tl(Responders));
        {error, closed} ->
            Module:close(Socket)
    end.

listen(ssl) ->
    Opts = [
        {packet, http},
        binary,
        {active, false},
        {ip, {127,0,0,1}},
        {verify,0},
        {keyfile, "test/key.pem"},
        {certfile, "test/crt.pem"}
    ],
    {ok, LS} = ssl:listen(0, Opts),
    LS;
listen(Module) ->
    {ok, LS} = Module:listen(0, [
            {packet, http},
            binary,
            {active, false},
            {ip, {127,0,0,1}}
        ]),
    LS.

accept(ssl, ListenSocket) ->
    {ok, Socket} = ssl:transport_accept(ListenSocket, 10000),
    ok = ssl:ssl_accept(Socket),
    Socket;
accept(Module, ListenSocket) ->
    {ok, Socket} = Module:accept(ListenSocket, 1000),
    Socket.

setopts(ssl, Socket, Options) ->
    ssl:setopts(Socket, Options);
setopts(_, Socket, Options) ->
    inet:setopts(Socket, Options).

port(ssl, Socket) ->
    {ok, {_, Port}} = ssl:sockname(Socket),
    Port;
port(_, Socket) ->
    {ok, Port} = inet:port(Socket),
    Port.