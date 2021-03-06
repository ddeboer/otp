%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2018-2018. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
%%

-module(ssl_eqc_handshake).

-compile(export_all).

-proptest(eqc).
-proptest([triq,proper]).

-ifndef(EQC).
-ifndef(PROPER).
-ifndef(TRIQ).
-define(EQC,true).
-endif.
-endif.
-endif.

-ifdef(EQC).
-include_lib("eqc/include/eqc.hrl").
-define(MOD_eqc,eqc).

-else.
-ifdef(PROPER).
-include_lib("proper/include/proper.hrl").
-define(MOD_eqc,proper).

-else.
-ifdef(TRIQ).
-define(MOD_eqc,triq).
-include_lib("triq/include/triq.hrl").

-endif.
-endif.
-endif.

-include_lib("kernel/include/inet.hrl").
-include_lib("ssl/src/tls_handshake_1_3.hrl").
-include_lib("ssl/src/tls_handshake.hrl").
-include_lib("ssl/src/ssl_handshake.hrl").
-include_lib("ssl/src/ssl_alert.hrl").
-include_lib("ssl/src/ssl_internal.hrl").

-define('TLS_v1.3', {3,4}).
-define('TLS_v1.2', {3,3}).
-define('TLS_v1.1', {3,2}).
-define('TLS_v1',   {3,1}).
-define('SSL_v3',   {3,0}).

%%--------------------------------------------------------------------
%% Properties --------------------------------------------------------
%%--------------------------------------------------------------------

prop_tls_hs_encode_decode() ->
    ?FORALL({Handshake, TLSVersion}, ?LET(Version, tls_version(), {tls_msg(Version), Version}),
            try 
                [Type, _Length, Data] = tls_handshake:encode_handshake(Handshake, TLSVersion),
                case tls_handshake:decode_handshake(TLSVersion, Type, Data) of
                    Handshake ->
                        true;
                    _ ->
                        false
                end
            catch
                throw:#alert{} ->
                    true
            end
	   ).

%%--------------------------------------------------------------------
%% Message Generators  -----------------------------------------------
%%--------------------------------------------------------------------

tls_msg(?'TLS_v1.3'= Version) ->
    oneof([client_hello(Version),
           server_hello(Version),
           %%new_session_ticket()
          #end_of_early_data{},
           encrypted_extensions(),
           certificate_1_3(),
           %%certificate_request_1_3,
           %%certificate_verify()
           finished(),
           key_update()
          ]);
tls_msg(Version) ->
    oneof([
           #hello_request{},
           client_hello(Version),
           server_hello(Version),
           certificate(),
           %%server_key_exchange()
           certificate_request(Version),
           #server_hello_done{},
           %%certificate_verify()
           %%client_key_exchange()
           finished()
          ]).

%%
%% Shared messages
%%
client_hello(?'TLS_v1.3' = Version) ->
    #client_hello{session_id = session_id(),
		  client_version = ?'TLS_v1.2',
		  cipher_suites = cipher_suites(Version),
		  compression_methods = compressions(Version),
		  random = client_random(Version),
		  extensions = client_hello_extensions(Version)    
                 };
client_hello(Version) ->
    #client_hello{session_id = session_id(),
		  client_version = Version,
                  cipher_suites = cipher_suites(Version),
		  compression_methods = compressions(Version),
		  random = client_random(Version),
		  extensions = client_hello_extensions(Version)    
                 }.

server_hello(?'TLS_v1.3' = Version) ->
    #server_hello{server_version = ?'TLS_v1.2',
		  session_id = session_id(),
                  random = server_random(Version),
                  cipher_suite = cipher_suite(Version),
		  compression_method = compression(Version),
		  extensions = server_hello_extensions(Version)    
                 };
server_hello(Version) ->
    #server_hello{server_version = Version,
		  session_id = session_id(),
                  random = server_random(Version),
                  cipher_suite = cipher_suite(Version),
		  compression_method = compression(Version),
		  extensions = server_hello_extensions(Version)    
                 }.

certificate() ->
    #certificate{
       asn1_certificates = certificate_chain()
      }.

certificate_1_3() ->
     ?LET(Certs, certificate_chain(),
          #certificate_1_3{
             certificate_request_context = certificate_request_context(),
             entries = certificate_entries(Certs, [])  
            }).

finished() ->
    ?LET(Size, digest_size(),
         #finished{verify_data = crypto:strong_rand_bytes(Size)}).

%%
%% TLS 1.0-1.2 messages
%%



%%
%% TLS 1.3 messages
%%

encrypted_extensions() ->
    ?LET(Exts, extensions(?'TLS_v1.3', encrypted_extensions),
         #encrypted_extensions{extensions = Exts}).


key_update() ->
    #key_update{request_update = request_update()}.


%%--------------------------------------------------------------------
%% Messge Data Generators  -------------------------------------------
%%--------------------------------------------------------------------

tls_version() ->
    oneof([?'TLS_v1.3', ?'TLS_v1.2', ?'TLS_v1.1', ?'TLS_v1', ?'SSL_v3']).

cipher_suite(Version) ->
    oneof(cipher_suites(Version)).

cipher_suites(Version) ->
    ssl_cipher:suites(Version).

session_id() ->
    crypto:strong_rand_bytes(?NUM_OF_SESSION_ID_BYTES).
 
compression(Version) ->
     oneof(compressions(Version)).

compressions(_) -> 
    ssl_record:compressions().

client_random(_) ->
    crypto:strong_rand_bytes(32).

server_random(_) ->
    crypto:strong_rand_bytes(32).


client_hello_extensions(Version) ->
    ?LET(Exts, extensions(Version, client_hello),
         maps:merge(ssl_handshake:empty_extensions(Version, client_hello),
                    Exts)).

server_hello_extensions(Version) ->
    ?LET(Exts, extensions(Version, server_hello),
         maps:merge(ssl_handshake:empty_extensions(Version, server_hello),
                    Exts)).

key_share_client_hello() ->
     oneof([undefined]).
    %%oneof([#key_share_client_hello{}, undefined]).

key_share_server_hello() ->
     oneof([undefined]).
    %%oneof([#key_share_server_hello{}, undefined]).

pre_shared_keyextension() ->
     oneof([undefined]).
     %%oneof([#pre_shared_keyextension{},undefined]).

%% +--------------------------------------------------+-------------+
%% | Extension                                        |     TLS 1.3 |
%% +--------------------------------------------------+-------------+
%% | server_name [RFC6066]                            |      CH, EE |
%% |                                                  |             |
%% | max_fragment_length [RFC6066]                    |      CH, EE |
%% |                                                  |             |
%% | status_request [RFC6066]                         |  CH, CR, CT |
%% |                                                  |             |
%% | supported_groups [RFC7919]                       |      CH, EE |
%% |                                                  |             |
%% | signature_algorithms (RFC 8446)                  |      CH, CR |
%% |                                                  |             |
%% | use_srtp [RFC5764]                               |      CH, EE |
%% |                                                  |             |
%% | heartbeat [RFC6520]                              |      CH, EE |
%% |                                                  |             |
%% | application_layer_protocol_negotiation [RFC7301] |      CH, EE |
%% |                                                  |             |
%% | signed_certificate_timestamp [RFC6962]           |  CH, CR, CT |
%% |                                                  |             |
%% | client_certificate_type [RFC7250]                |      CH, EE |
%% |                                                  |             |
%% | server_certificate_type [RFC7250]                |      CH, EE |
%% |                                                  |             |
%% | padding [RFC7685]                                |          CH |
%% |                                                  |             |
%% | key_share (RFC 8446)                             | CH, SH, HRR |
%% |                                                  |             |
%% | pre_shared_key (RFC 8446)                        |      CH, SH |
%% |                                                  |             |
%% | psk_key_exchange_modes (RFC 8446)                |          CH |
%% |                                                  |             |
%% | early_data (RFC 8446)                            | CH, EE, NST |
%% |                                                  |             |
%% | cookie (RFC 8446)                                |     CH, HRR |
%% |                                                  |             |
%% | supported_versions (RFC 8446)                    | CH, SH, HRR |
%% |                                                  |             |
%% | certificate_authorities (RFC 8446)               |      CH, CR |
%% |                                                  |             |
%% | oid_filters (RFC 8446)                           |          CR |
%% |                                                  |             |
%% | post_handshake_auth (RFC 8446)                   |          CH |
%% |                                                  |             |
%% | signature_algorithms_cert (RFC 8446)             |      CH, CR |
%% +--------------------------------------------------+-------------+
extensions(?'TLS_v1.3' = Version, client_hello) ->
     ?LET({
           ServerName,
           %% MaxFragmentLength,
           %% StatusRequest,
           SupportedGroups,
           SignatureAlgorithms,
           %% UseSrtp,
           %% Heartbeat,
           ALPN,
           %% SignedCertTimestamp,
           %% ClientCertiticateType,
           %% ServerCertificateType,
           %% Padding,
           %% KeyShare,
           %% PreSharedKey,
           %% PSKKeyExchangeModes,
           %% EarlyData,
           %% Cookie,
           SupportedVersions,
           %% CertAuthorities,
           %% PostHandshakeAuth,
           SignatureAlgorithmsCert
          },
          {
           oneof([server_name(), undefined]),
           %% oneof([max_fragment_length(), undefined]),
           %% oneof([status_request(), undefined]),
           oneof([supported_groups(Version), undefined]),
           oneof([signature_algs(Version), undefined]),
           %% oneof([use_srtp(), undefined]),
           %% oneof([heartbeat(), undefined]),
           oneof([alpn(), undefined]),
           %% oneof([signed_cert_timestamp(), undefined]),
           %% oneof([client_cert_type(), undefined]),
           %% oneof([server_cert_type(), undefined]),
           %% oneof([padding(), undefined]),
           %% oneof([key_share(), undefined]),
           %% oneof([pre_shared_key(), undefined]),
           %% oneof([psk_key_exchange_modes(), undefined]),
           %% oneof([early_data(), undefined]),
           %% oneof([cookie(), undefined]),
           oneof([client_hello_versions(Version), undefined]),
           %% oneof([cert_authorities(), undefined]),
           %% oneof([post_handshake_auth(), undefined]),
           oneof([signature_algs_cert(), undefined])
          },
          maps:filter(fun(_, undefined) ->
                              false;
                         (_,_) ->
                              true
                      end,
                      #{
                        sni => ServerName,
                        %% max_fragment_length => MaxFragmentLength,
                        %% status_request => StatusRequest,
                        elliptic_curves => SupportedGroups,
                        signature_algs => SignatureAlgorithms,
                        %% use_srtp => UseSrtp,
                        %% heartbeat => Heartbeat,
                        alpn => ALPN,
                        %% signed_cert_timestamp => SignedCertTimestamp,
                        %% client_cert_type => ClientCertificateType,
                        %% server_cert_type => ServerCertificateType,
                        %% padding => Padding,
                        %% key_share => KeyShare,
                        %% pre_shared_key => PreSharedKey,
                        %% psk_key_exhange_modes => PSKKeyExchangeModes,
                        %% early_data => EarlyData,
                        %% cookie => Cookie,
                        client_hello_versions => SupportedVersions,
                        %% cert_authorities => CertAuthorities,
                        %% post_handshake_auth => PostHandshakeAuth,
                        signature_algs_cert => SignatureAlgorithmsCert
                       }));
extensions(?'SSL_v3', client_hello) ->
    #{};
extensions(Version, client_hello) ->
    ?LET({
          SNI,
          ECPoitF,
          ECCurves,
          ALPN,
          NextP,
          SRP
          %% RenegotiationInfo
         },
         {
          oneof([sni(), undefined]),
          oneof([ec_point_formats(), undefined]),
          oneof([elliptic_curves(Version), undefined]), 
          oneof([alpn(),  undefined]), 
          oneof([next_protocol_negotiation(), undefined]),
          oneof([srp(), undefined])
          %% oneof([renegotiation_info(), undefined])
         },
         maps:filter(fun(_, undefined) -> 
                             false;
                        (_,_) -> 
                             true 
                     end, 
                     #{
                       sni => SNI,
                       ec_point_formats => ECPoitF,
                       elliptic_curves => ECCurves,
                       alpn => ALPN,
                       next_protocol_negotiation => NextP,
                       srp => SRP
                       %% renegotiation_info => RenegotiationInfo
                      }));
extensions(?'TLS_v1.3' = Version, server_hello) ->
    ?LET({
          %% KeyShare,
          %% PreSharedKeys,
          SupportedVersions
         },
         {
          %% oneof([key_share(), undefined]),
          %% oneof([pre_shared_keys(),  undefined]),
          oneof([server_hello_selected_version(), undefined])
         },
         maps:filter(fun(_, undefined) ->
                             false;
                        (_,_) ->
                             true
                     end,
                     #{
                       %% key_share => KeyShare,
                       %% pre_shared_keys => PreSharedKeys,
                       server_hello_selected_version => SupportedVersions
                      }));
extensions(Version, server_hello) ->
    ?LET({
          ECPoitF,
          ALPN,
          NextP
          %% RenegotiationInfo,
         },
         {
          oneof([ec_point_formats(), undefined]),
          oneof([alpn(),  undefined]),
          oneof([next_protocol_negotiation(), undefined])
          %% oneof([renegotiation_info(), undefined]),
         },
         maps:filter(fun(_, undefined) ->
                             false;
                        (_,_) ->
                             true
                     end,
                     #{
                       ec_point_formats => ECPoitF,
                       alpn => ALPN,
                       next_protocol_negotiation => NextP
                       %% renegotiation_info => RenegotiationInfo
                      }));
extensions(?'TLS_v1.3' = Version, encrypted_extensions) ->
     ?LET({
           ServerName,
           %% MaxFragmentLength,
           SupportedGroups,
           %% UseSrtp,
           %% Heartbeat,
           ALPN
           %% ClientCertiticateType,
           %% ServerCertificateType,
           %% EarlyData
          },
          {
           oneof([server_name(), undefined]),
           %% oneof([max_fragment_length(), undefined]),
           oneof([supported_groups(Version), undefined]),
           %% oneof([use_srtp(), undefined]),
           %% oneof([heartbeat(), undefined]),
           oneof([alpn(), undefined])
           %% oneof([client_cert_type(), undefined]),
           %% oneof([server_cert_type(), undefined]),
           %% oneof([early_data(), undefined])
          },
          maps:filter(fun(_, undefined) ->
                              false;
                         (_,_) ->
                              true
                      end,
                      #{
                        sni => ServerName,
                        %% max_fragment_length => MaxFragmentLength,
                        elliptic_curves => SupportedGroups,
                        %% use_srtp => UseSrtp,
                        %% heartbeat => Heartbeat,
                        alpn => ALPN
                        %% client_cert_type => ClientCertificateType,
                        %% server_cert_type => ServerCertificateType,
                        %% early_data => EarlyData
                       })).

server_name() ->
  ?LET(ServerName, sni(),
       ServerName).
    %% sni().

signature_algs_cert() ->
    ?LET(List,  sig_scheme_list(),
         #signature_algorithms_cert{signature_scheme_list = List}).

signature_algorithms() ->
    ?LET(List,  sig_scheme_list(), 
         #signature_algorithms{signature_scheme_list = List}).

sig_scheme_list() ->
    oneof([[rsa_pkcs1_sha256],
           [rsa_pkcs1_sha256, ecdsa_sha1],
           [rsa_pkcs1_sha256,
            rsa_pkcs1_sha384,
            rsa_pkcs1_sha512,
            ecdsa_secp256r1_sha256,
            ecdsa_secp384r1_sha384,
            ecdsa_secp521r1_sha512,
            rsa_pss_rsae_sha256,
            rsa_pss_rsae_sha384,
            rsa_pss_rsae_sha512,
            rsa_pss_pss_sha256,
            rsa_pss_pss_sha384,
            rsa_pss_pss_sha512,
            rsa_pkcs1_sha1,
            ecdsa_sha1]
          ]).

client_hello_versions(?'TLS_v1.3') ->
    ?LET(SupportedVersions,
         oneof([[{3,4}],
                [{3,3},{3,4}],
                [{3,4},{3,3},{3,2},{3,1},{3,0}]
               ]),
        #client_hello_versions{versions = SupportedVersions});
client_hello_versions(_) ->
    ?LET(SupportedVersions,
         oneof([[{3,3}],
                [{3,3},{3,2}],
                [{3,3},{3,2},{3,1},{3,0}]
               ]),
        #client_hello_versions{versions = SupportedVersions}).

server_hello_selected_version() ->
    #server_hello_selected_version{selected_version = {3,4}}.

request_update() ->
     oneof([?UPDATE_NOT_REQUESTED, ?UPDATE_REQUESTED]).

certificate_chain()->
    Conf = cert_conf(),
    ?LET(Chain, 
         choose_certificate_chain(Conf),
         Chain).

choose_certificate_chain(#{server_config := ServerConf,
                           client_config := ClientConf}) -> 
    oneof([certificate_chain(ServerConf), certificate_chain(ClientConf)]).

certificate_request_context() ->
    <<>>.
certificate_entries([], Acc) ->
    lists:reverse(Acc);
certificate_entries([Cert | Rest], Acc) ->
    certificate_entries(Rest, [certificate_entry(Cert) | Acc]).

certificate_entry(Cert) ->
    #certificate_entry{data = Cert,
                       extensions = certificate_entry_extensions()
                      }.
certificate_entry_extensions() ->
    #{}.

certificate_chain(Conf) ->  
    CAs = proplists:get_value(cacerts, Conf),
    Cert = proplists:get_value(cert, Conf),
    %% Middle argument are of correct type but will not be used
    {ok, _, Chain} = ssl_certificate:certificate_chain(Cert, ets:new(foo, []), make_ref(), CAs), 
    Chain.

cert_conf()->
    Hostname = net_adm:localhost(),
    {ok, #hostent{h_addr_list = [_IP |_]}} = inet:gethostbyname(net_adm:localhost()),
    public_key:pkix_test_data(#{server_chain => 
                                    #{root => [{key, ssl_test_lib:hardcode_rsa_key(1)}],
                                      intermediates => [[{key, ssl_test_lib:hardcode_rsa_key(2)}]],
                                      peer => [{extensions, [#'Extension'{extnID = 
                                                                              ?'id-ce-subjectAltName',
                                                                          extnValue = [{dNSName, Hostname}],
                                                                          critical = false}]},
                                               {key, ssl_test_lib:hardcode_rsa_key(3)}
                                              ]},
                                client_chain => 
                                    #{root => [{key, ssl_test_lib:hardcode_rsa_key(4)}],
                                      intermediates => [[{key, ssl_test_lib:hardcode_rsa_key(5)}]],
                                      peer => [{key, ssl_test_lib:hardcode_rsa_key(6)}]}}).

certificate_request(Version) ->
    #certificate_request{certificate_types = certificate_types(Version),
			 hashsign_algorithms = hashsign_algorithms(Version),
			 certificate_authorities = certificate_authorities()}.

certificate_types(?'TLS_v1.3') ->
    iolist_to_binary([<<?BYTE(?ECDSA_SIGN)>>, <<?BYTE(?RSA_SIGN)>>]);
certificate_types(?'TLS_v1.2') ->
    iolist_to_binary([<<?BYTE(?ECDSA_SIGN)>>, <<?BYTE(?RSA_SIGN)>>, <<?BYTE(?DSS_SIGN)>>]);
certificate_types(_) ->
    iolist_to_binary([<<?BYTE(?ECDSA_SIGN)>>, <<?BYTE(?RSA_SIGN)>>, <<?BYTE(?DSS_SIGN)>>]).



signature_algs({3,4}) ->
    ?LET(Algs, signature_algorithms(),
         Algs);
signature_algs({3,3} = Version) ->
        #hash_sign_algos{hash_sign_algos = hash_alg_list(Version)};
signature_algs(Version) when Version < {3,3} ->
    undefined.



hashsign_algorithms({_, N} = Version) when N >= 3 ->                                 
    #hash_sign_algos{hash_sign_algos = hash_alg_list(Version)};
hashsign_algorithms(_) -> 
    undefined.

hash_alg_list(Version) ->
    ?LET(NumOf, choose(1,15),
	 ?LET(List, [hash_alg(Version) || _ <- lists:seq(1,NumOf)],
	      lists:usort(List)
             )).
    
hash_alg(Version) ->
   ?LET(Alg, sign_algorithm(Version),
         {hash_algorithm(Version, Alg), Alg}
       ).

hash_algorithm(?'TLS_v1.3', _) ->
    oneof([sha, sha224, sha256, sha384, sha512]);
hash_algorithm(?'TLS_v1.2', rsa) ->
    oneof([sha, sha224, sha256, sha384, sha512]);
hash_algorithm(_, rsa) ->
    oneof([md5, sha, sha224, sha256, sha384, sha512]);
hash_algorithm(_, ecdsa) ->
    oneof([sha, sha224, sha256, sha384, sha512]);
hash_algorithm(_, dsa) ->
    sha.

sign_algorithm(?'TLS_v1.3') ->
    oneof([rsa, ecdsa]);
sign_algorithm(_) ->
    oneof([rsa, dsa, ecdsa]).

certificate_authorities() ->
    #{server_config := ServerConf} = cert_conf(), 
    Authorities = proplists:get_value(cacerts, ServerConf),
    Enc = fun(#'OTPCertificate'{tbsCertificate=TBSCert}) ->
		  OTPSubj = TBSCert#'OTPTBSCertificate'.subject,
		  DNEncodedBin = public_key:pkix_encode('Name', OTPSubj, otp),
		  DNEncodedLen = byte_size(DNEncodedBin),
		  <<?UINT16(DNEncodedLen), DNEncodedBin/binary>>
	  end,
    list_to_binary([Enc(public_key:pkix_decode_cert(DERCert, otp)) || DERCert <- Authorities]).

digest_size()->
   oneof([160,224,256,384,512]).

key_share_entry() ->
    undefined.
    %%#key_share_entry{}.

server_hello_selected_version(Version) ->
    #server_hello_selected_version{selected_version = Version}.

sni() ->
    #sni{hostname = net_adm:localhost()}.

ec_point_formats() ->
    #ec_point_formats{ec_point_format_list = ec_point_format_list()}.
 
ec_point_format_list() ->
    [?ECPOINT_UNCOMPRESSED].

elliptic_curves({_, Minor}) when Minor < 4 ->
    Curves = tls_v1:ecc_curves(Minor),
    #elliptic_curves{elliptic_curve_list = Curves}.

%% RFC 8446 (TLS 1.3) renamed the "elliptic_curve" extension.
supported_groups({_, Minor}) when Minor >= 4 ->
    SupportedGroups = tls_v1:groups(Minor),
    #supported_groups{supported_groups = SupportedGroups}.


alpn() ->
    ?LET(ExtD,  alpn_protocols(), #alpn{extension_data = ExtD}).

alpn_protocols() ->
    oneof([<<"spdy/2">>, <<"spdy/3">>, <<"http/2">>, <<"http/1.0">>, <<"http/1.1">>]).
    
next_protocol_negotiation() ->
   %% Predecessor to APLN
    ?LET(ExtD,  alpn_protocols(), #next_protocol_negotiation{extension_data = ExtD}).

srp() ->
   ?LET(Name, gen_name(),  #srp{username = list_to_binary(Name)}).

renegotiation_info() ->
    #renegotiation_info{renegotiated_connection = 0}.

gen_name() -> 
    ?LET(Size, choose(1,10), gen_string(Size)).

gen_char() -> 
    choose($a,$z).

gen_string(N) ->
    gen_string(N, []).

gen_string(0, Acc) ->
    Acc;
gen_string(N, Acc) ->
    ?LET(Char, gen_char(), gen_string(N-1, [Char | Acc])).
