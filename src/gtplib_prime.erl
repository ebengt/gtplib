%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at http://mozilla.org/MPL/2.0/.

%% Copyright 2015, Travelping GmbH <info@travelping.com>

%% Documentation
%% http://www.etsi.org/deliver/etsi_ts/132200_132299/132295/14.00.00_60/ts_132295v140000p.pdf
%% http://www.etsi.org/deliver/etsi_ts/129000_129099/129060/12.06.00_60/ts_129060v120600p.pdf
-module( gtplib_prime ).

-export( [encode/4, decode/5] ).

-type prime_type() :: atom().
-type ei() :: tuple().

 -include( "gtp_packet.hrl" ).

-define( TLV_ADDRESS_OF_RECOMMENED_NODE, 254 ).
-define( TLV_CHARGING_GATEWAY_ADDRESS, 251 ).


-spec( encode( Version::atom(), Type::prime_type(), Sequence::number(), [ei()] ) -> binary() ).
encode( Version, Type, Sequence, EIs ) ->
	V = version( Version ),
	T = type( Type ),
	D = data( Type, EIs ),
	L = erlang:byte_size( D ),
	Filler = version_filler( Version ),
	binary:list_to_bin( [<<V:8, T:8, L:16, Sequence:16>>, Filler, D] ).

-spec( decode( atom(), number(), number(), number(), binary() ) -> #gtp{} ).
decode( Version, Type, _Length, Sequence, Data ) ->
	T = type( Type ),
	IE = data( T, Data ),
	#gtp{version = Version, type = T, seq_no = Sequence, ie = IE}.

%%====================================================================
%% Internal functions
%%====================================================================

address( TLV, {A, B, C, D} ) -> <<TLV:8, 4:8, A:8, B:8, C:8, D:8>>;
address( TLV, {A, B, C, D, E, F, G, H} ) -> <<TLV:8, 8:8, A:16, B:16, C:16, D:16, E:16, F:16, G:16, H:16>>;
address( _TLV, undefined ) -> <<>>;
address( TLV, <<TLV:8, 4:8, A:8, B:8, C:8, D:8, T/binary>> ) -> {{A, B, C, D}, T};
address( TLV, <<TLV:8, 8:8, A:16, B:16, C:16, D:16, E:16, F:16, G:16, H:16, T/binary>> ) -> {{A, B, C, D, E, F, G, H}, T};
address( _TLV, <<_/binary>> ) -> {undefined, <<>>}.

data( echo_request, [] ) -> <<>>;
data( echo_request, undefined ) -> <<>>;
data( echo_request, <<_/binary>> ) -> #{};
data( echo_response, IEs ) when is_list(IEs) -> gtp_packet:encode_v1( echo_response, IEs );
data( echo_response, <<14:8, RC:8, _/binary>> ) -> #{{recovery, 0} => #recovery{restart_counter=RC}};
data( echo_response, <<_/binary>> ) -> #{};
data( version_not_supported, [] ) -> <<>>;
data( version_not_supported, undefined ) -> <<>>;
data( version_not_supported, <<_/binary>> ) -> #{};
data( node_alive_request, [#node_addresses{node=N, alternative_node=A}] ) ->
	binary:list_to_bin( [address(?TLV_CHARGING_GATEWAY_ADDRESS, N), address(?TLV_CHARGING_GATEWAY_ADDRESS, A)] );
data( node_alive_request, Binary ) ->
	{Node, T} = address( ?TLV_CHARGING_GATEWAY_ADDRESS, Binary ),
	{Alternative, _T} = address( ?TLV_CHARGING_GATEWAY_ADDRESS, T ),
	#{{node_addresses, 0} => #node_addresses{node=Node, alternative_node=Alternative}};
data( node_alive_response, [] ) -> <<>>;
data( node_alive_response, undefined) -> <<>>;
data( node_alive_response, <<_/binary>> ) -> #{};
data( redirection_request, [#cause{}=R | T] ) ->
	{_, C} = gtp_packet:encode_v1_element( R ),
	A = optional( T ),
	binary:list_to_bin( [C, A] );
data( redirection_request, <<1:8, Cause:8/bits, Binary/binary>> ) ->
	C = gtp_packet:decode_v1_element( Cause, 1, 0 ), % Same 1 as in 1:8
	{Node, T} = address( ?TLV_ADDRESS_OF_RECOMMENED_NODE, Binary ),
	{Alternative, _T} = address( ?TLV_ADDRESS_OF_RECOMMENED_NODE, T ),
	M = map_recommended_node( Node, Alternative ),
	M#{{cause, 0} => C};
data( redirection_response, [#cause{}=R] ) ->
	{_, C} = gtp_packet:encode_v1_element( R ),
	C;
data( redirection_response, <<1:8, Cause:8/bits, _T/binary>> ) ->
	C = gtp_packet:decode_v1_element( Cause, 1, 0 ), % Same 1 as in 1:8
	#{{cause, 0} => C};
data( data_record_transfer_request, [#packet_transfer{}=R] ) -> packet_transfer( R );
%% Only send_data_record_packet for now.
data( data_record_transfer_request, <<126:8, 1:8, Binary/binary>> ) -> packet_transfer( Binary );
data( data_record_transfer_response, [#cause{}=R, #packet_transfer{respondeds=Sequences}] ) ->
	{_, C} = gtp_packet:encode_v1_element( R ),
	L = 2 * erlang:length( Sequences ), % Two bytes per sequence
	SBs = [<<X:16>> || X <- Sequences],
	binary:list_to_bin( [C, <<253:8>>, <<L:16>> | SBs] );
%% Only send_data_record_packet for now.
data( data_record_transfer_response, <<1:8, Cause:8/bits, Binary/binary>> ) ->
	C = gtp_packet:decode_v1_element( Cause, 1, 0 ), % Same 1 as in 1:8
	<<253:8, _Length:16, Sequences/binary>> = Binary,
	S = [X || <<X:16>> <= Sequences],
	#{{cause, 0} => C, {packet_transfer, 0} => #packet_transfer{respondeds=S}}.

map_recommended_node( undefined, undefined ) -> #{};
map_recommended_node( Node, Alternative ) ->
	#{{node_addresses, 0} => #node_addresses{node=Node, alternative_node=Alternative}}.

optional( [] ) -> <<>>;
optional( [#node_addresses{node=N, alternative_node=A}] ) ->
	BN = address( ?TLV_ADDRESS_OF_RECOMMENED_NODE, N ),
	BA = address( ?TLV_ADDRESS_OF_RECOMMENED_NODE, A ),
	binary:list_to_bin( [BN, BA] ).

%% Only send_data_record_packet for now.
packet_transfer( #packet_transfer{command=send_data_record_packet, datas=Ds} ) ->
	C = packet_transfer_command( send_data_record_packet ),
	Type = <<252:8>>,
	Ps = [packet_transfer_length_before_packet(X) || X <- Ds],
	Bytes = packet_transfer_bytes( Ps ),
	N = erlang:length( Ps ),
	%% From 6.3.1 Standard Data Record Format and 6.4 Data Record Format Version for CDRs 
	%% Ber, GTP prime application, Release Identifier, Version Identifier
	Format = <<1:8, 1:4, 3:4, 5:8>>,
	binary:list_to_bin( [C, Type, <<Bytes:16>>, <<N:8>>, Format | Ps] );
%% Hard coding the only type/format/version we know.
packet_transfer( <<252:8, _Length:16, _Number_of_packets:8, 1:8, 1:4, 3:4, 5:8, Binary/binary>> ) ->
	Ds = [X || <<Length:16, X:Length/binary>> <= Binary],
	#{{data_record_transfer_request, 0} => #packet_transfer{command=send_data_record_packet, datas=Ds}}.

packet_transfer_bytes( Binary_packets ) -> lists:sum( [X || [<<X:16>>, _] <- Binary_packets] ).

packet_transfer_command( send_data_record_packet ) -> <<126:8, 1:8>>.

packet_transfer_length_before_packet( Packet ) ->
	L = erlang:byte_size( Packet ),
	[<<L:16>>, Packet].

%% For the first time I benefit from -compile(export_all).
type( T ) -> gtp_packet:message_type_v1( T ).


%% e => 0:3, 0:1, 7:3, 0:1
version( prime_v0 ) -> 16#e;
%% f => 0:3, 0:1, 7:3, 1:1
version( prime_v0_short ) -> 16#f;
%% 2e => 2:3, 0:1, 7:3, 0:1
version( prime_v1 ) -> 16#2e;
%% 4e => 2:3, 0:1, 7:3, 0:1
version( prime_v2 ) -> 16#4e.

version_filler( prime_v0 ) -> <<0:(14*8)>>;
version_filler( prime_v0_short ) -> <<>>;
version_filler( prime_v1 ) -> <<0:(14*8)>>;
version_filler( prime_v2 ) -> <<>>.
