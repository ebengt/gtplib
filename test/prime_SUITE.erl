-module( prime_SUITE ).

-export( [encode_decode/1, v0/1, v0_short/1, v1/1] ).

-include( "gtp_packet.hrl" ).

%% Callbacks

-export( [all/0, init_per_suite/1, end_per_suite/1] ).

all() -> [encode_decode, v0, v0_short, v1].

init_per_suite( Config ) -> Config.

end_per_suite( _Config ) -> ok.

%% Tests

encode_decode( _Config ) -> [encode_decode_check(X) || X <- prime_all()].

v0( _Config ) ->
	P = #gtp{version = prime_v0, type = version_not_supported, seq_no = 0},
	V0 = gtp_packet:encode( P ),
	Pmap = gtp_packet:decode( V0 ),
	header_check( P, Pmap ).
	
v0_short( _Config ) ->
	P = #gtp{version = prime_v0_short, type = version_not_supported, seq_no = 0},
	V0 = gtp_packet:encode( P ),
	Pmap = gtp_packet:decode( V0 ),
	header_check( P, Pmap ).

v1( _Config ) ->
	P = #gtp{version = prime_v1, type = version_not_supported, seq_no = 0},
	V1 = gtp_packet:encode( P ),
	Pmap = gtp_packet:decode( V1 ),
	header_check( P, Pmap ).
	

%%====================================================================
%% Internal functions
%%====================================================================

encode_decode_check( T ) ->
	P = prime_package( T ),
	B = gtp_packet:encode( P ),
	Pmap = gtp_packet:decode( B ),
	header_check( P, Pmap ),
	M = map( P#gtp.ie ),
	%% Debugging test case.
	{M, M} = {M, Pmap#gtp.ie}.

header_check( P, Pmap ) ->
	true = (P#gtp.version =:= Pmap#gtp.version),
	true = (P#gtp.type =:= Pmap#gtp.type),
	true = (P#gtp.seq_no =:= Pmap#gtp.seq_no).

map( [] ) -> #{};
map( [#recovery{}=R] ) -> #{{recovery, 0} => R};
map( [#cause{}=R] ) -> #{{cause, 0} => R};
map( [#node_addresses{}=R] ) -> #{{node_addresses, 0} => R};
map( [#cause{}=R, #node_addresses{}=R2] ) -> #{{cause, 0} => R, {node_addresses, 0} => R2};
map( [#packet_transfer{}=R] ) -> #{{data_record_transfer_request, 0} => R};
map( [#cause{}=R, #packet_transfer{}=R2] ) -> #{{cause, 0} => R, {packet_transfer, 0} => R2}.

prime_all() -> [echo_request, echo_response, version_not_supported, node_alive_request, node_alive_response, redirection_request, redirection_response, data_record_transfer_request, data_record_transfer_response].

prime_ei( echo_request ) -> [];
prime_ei( echo_response ) -> [#recovery{}];
prime_ei( version_not_supported ) -> [];
prime_ei( node_alive_request ) -> [#node_addresses{node = {1,2,3,4}}];
prime_ei( node_alive_response ) -> [];
prime_ei( redirection_request ) ->
	[#cause{value=another_node_is_about_to_go_down}, #node_addresses{node = {1,2,3,4}, alternative_node = {1,2,3,4, 1,2,3,4}}];
prime_ei( redirection_response ) -> [#cause{value=request_accepted}];
prime_ei( data_record_transfer_request ) -> [#packet_transfer{command = send_data_record_packet, datas = [<<1,2,3,4>>]}];
prime_ei( data_record_transfer_response ) -> [#cause{value=request_accepted}, #packet_transfer{respondeds=[1,2,3,4]}].

prime_header( T ) -> #gtp{version = prime_v2, type = T, seq_no = 0}.

prime_package( T ) ->
	P = prime_header( T ),
	P#gtp{ie = prime_ei(T)}.
