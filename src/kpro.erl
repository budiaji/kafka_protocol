%%%   Copyright (c) 2014-2018, Klarna AB
%%%
%%%   Licensed under the Apache License, Version 2.0 (the "License");
%%%   you may not use this file except in compliance with the License.
%%%   You may obtain a copy of the License at
%%%
%%%       http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%   Unless required by applicable law or agreed to in writing, software
%%%   distributed under the License is distributed on an "AS IS" BASIS,
%%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%%   See the License for the specific language governing permissions and
%%%   limitations under the License.
%%%

-module(kpro).

%% Connection
-export([ close_connection/1
        , connect_any/2
        , connect_controller/2
        , connect_controller/3
        , connect_coordinator/3
        , connect_partition_leader/4
        , connect_partition_leader/5
        ]).

%% Broker properties
-export([ discover_coordinator/4
        , discover_partition_leader/4
        , get_api_versions/1
        , get_api_vsn_range/2
        ]).

%% Primitive RPCs
-export([ request_sync/3
        , request_async/2
        ]).

%% Transactional RPCs
-export([ txn_abort/1
        , txn_abort/2
        , txn_commit/1
        , txn_commit/2
        , txn_init_ctx/2
        , txn_init_ctx/3
        , txn_offset_commit/4
        , txn_offset_commit/5
        , txn_send_cg/2
        , txn_send_cg/3
        , txn_send_partitions/2
        , txn_send_partitions/3
        ]).

%% request makers/response parsers
%% there are more in `kpro_req_lib'
-export([ encode_request/3
        , make_request/3
        , parse_response/1
        ]).

%% misc
-export([ decode_batches/1
        , find/2
        , find/3
        , parse_endpoints/1
        , parse_endpoints/2
        ]).

-export_type([ api/0
             , batch_decode_result/0
             , batch_input/0
             , batch_meta/0
             , bytes/0
             , client_id/0
             , compress_option/0
             , connection/0
             , conn_config/0
             , coordinator_type/0
             , corr_id/0
             , count/0
             , endpoint/0
             , error_code/0
             , field_name/0
             , field_value/0
             , group_id/0
             , headers/0
             , header_key/0
             , header_val/0
             , hostname/0
             , incomplete_batch/0
             , int8/0
             , int16/0
             , int32/0
             , int64/0
             , isolation_level/0
             , key/0
             , kv_list/0
             , magic/0
             , message/0
             , msg_ts/0
             , offset/0
             , offsets_to_commit/0
             , partition/0
             , portnum/0
             , primitive/0
             , primitive_type/0
             , produce_opts/0
             , producer_epoch/0
             , producer_id/0
             , protocol/0
             , req/0
             , required_acks/0
             , rsp/0
             , schema/0
             , seqno/0
             , stack/0
             , str/0
             , struct/0
             , timestamp_type/0
             , transactional_id/0
             , txn_ctx/0
             , topic/0
             , value/0
             , vsn/0
             , vsn_range/0
             , vsn_ranges/0
             , wait/0
             ]).

-include("kpro_private.hrl").

-type int8()       :: -128..127.
-type int16()      :: -32768..32767.
-type int32()      :: -2147483648..2147483647.
-type int64()      :: -9223372036854775808..9223372036854775807.
-type str()        :: ?null | string() | binary().
-type bytes()      :: binary().
-type error_code() :: int16() | atom().
-type msg_ts() :: int64().
-type producer_id() :: int64().
-type magic() :: int8().

-type client_id() :: binary().
-type hostname() :: binary() | string().
-type portnum() :: non_neg_integer().
-type endpoint() :: {hostname(), portnum()}.
-type corr_id() :: int32().
-type topic() :: binary().
-type partition() :: int32().
-type offset() :: int64().

-type header_key() :: binary().
-type header_val() :: binary().
-type headers() :: [{header_key(), header_val()}].
-type seqno() :: non_neg_integer().
%% optional args to make produce request
-type produce_opts() :: #{ compression => compress_option() % common
                         , required_acks => required_acks() % common
                         , ack_timeout => wait() % common
                         , txn_ctx => txn_ctx() % txn only
                         , first_seqno => seqno() % txn only
                         }.

-type key() :: ?null | iodata().
-type value() :: ?null | iodata().
-type value_mabye_nested() :: value() | [{key(), kv_list()}].
-type kv_list() :: [kv() | tkv()].

-type msg_key() :: headers | ts | key | value.
-type msg_val() :: headers() | msg_ts() | key() | value().

-type kv() :: {key(), value_mabye_nested()}. % magic 0
-type tkv() :: {msg_ts(), key(), value_mabye_nested()}. % magic 1
-type msg_input() :: #{msg_key() => msg_val()}. % magic 2

-type batch_input() :: [kv()] % magic 0
                     | [tkv()] % magic 1
                     | [msg_input()]. % magic 2 non-transactional

-type incomplete_batch() :: ?incomplete_batch(int32()).
-type message() :: #kafka_message{}.
-type vsn() :: non_neg_integer().
-type count() :: non_neg_integer().
-type wait() :: non_neg_integer().
-type required_acks() :: -1..1 | all_isr | none | leader_only.
-type primitive() :: integer() | string() | binary() | atom().
-type field_name() :: atom().
-type field_value() :: primitive() | struct() | [struct()].
-type struct() :: #{field_name() => field_value()}
                | [{field_name(), field_value()}].
-type api() :: atom().
-type req() :: #kpro_req{}.
-type rsp() :: #kpro_rsp{}.
-type compress_option() :: ?no_compression
                         | ?gzip
                         | ?snappy
                         | ?lz4.
-type timestamp_type() :: undefined | create | append.
-type primitive_type() :: boolean
                        | int8
                        | int16
                        | int32
                        | int64
                        | varint
                        | string
                        | nullable_string
                        | bytes
                        | records.
-type decode_fun() :: fun((binary()) -> {field_value(), binary()}).
-type struct_schema() :: [{field_name(), schema()}].
-type schema() :: primitive_type()
                | struct_schema()
                | {array, schema()}
                | decode_fun(). %% caller defined decoder
-type stack() :: [{api(), vsn()} | field_name()]. %% encode / decode stack
-type isolation_level() :: read_committed | read_uncommitted.
-type connection() :: kpro_connection:connection().
-type conn_config() :: kpro_connection:config().
-type vsn_range() :: {vsn(), vsn()}.
-type vsn_ranges() :: #{api() => vsn_range()}.
-type protocol() :: plaintext | ssl | sasl_plaintext | sasl_ssl.
-type coordinator_type() :: group | txn.
-type group_id() :: binary().
-type transactional_id() :: binary().
-type producer_epoch() :: int16().
-type txn_ctx() :: #{ connection => connection()
                    , transactional_id => transactional_id()
                    , producer_id => producer_id()
                    , producer_epoch => producer_id()
                    }.
-type batch_meta_key() ::
        is_transaction % if this message was produced in a transaction
      | is_control % for read_uncommitted clients
      | last_offset % client wont have to do lists:last(Messages)
      | max_ts % client don't have to scan the messages for max
      | producer_id. % it can be referenced by a future fetch response in
                     % its aborted_transactions field
-type batch_meta_val() :: boolean() | atom() | integer().
-type batch_meta() :: ?KPRO_NO_BATCH_META %% magic 0-1
                    | #{batch_meta_key() => batch_meta_val()}.
-type batch_decode_result() :: ?incomplete_batch(int32())
                             | [{batch_meta(), [message()]}].
%% offset or offset + associated user-data to commit
-type offset_ud() :: offset() %% no user data
                   | {offset(), binary()}.
-type offsets_to_commit() :: #{{topic(), partition()} => offset_ud()}
                           | [{{topic(), partition()}, offset_ud()}].

%% All versions of kafka messages (records) share the same header:
%% Offset => int64
%% Length => int32
%% We need to at least fetch 12 bytes in order to fetch:
%%  - One complete non-compressed message when it is magic v0-1
%%  - Or one complete compressed batch when it is magic v0-1
%%    (magic v0-1 compressed batch is embedded in a wrapper message in a
%%     'recursive' manner)
%%  - Or one omplete batch when it is a magic v2 batch
-define(BATCH_LEADING_BYTES, 12).

%%%_* APIs =====================================================================

%% @see kpro_lib:parse_endpoints/2.
parse_endpoints(String) ->
  parse_endpoints(undefined, String).

%% @see kpro_lib:parse_endpoints/2.
-spec parse_endpoints(protocol() | undefined, string()) -> [endpoint()].
parse_endpoints(Protocol, String) ->
  kpro_lib:parse_endpoints(Protocol, String).

%% @doc Help function to make a request. See also kpro_req_lib for more help
%% functions.
-spec make_request(api(), vsn(), struct()) -> req().
make_request(Api, Vsn, Fields) ->
  kpro_req_lib:make(Api, Vsn, Fields).

%% @doc Help function to translate `#kpro_rsp{}' into a simpler term.
%% NOTE: This function is implemented with assumptions like:
%% topic-partition requests (list_offsets, produce, fetch etc.) are always sent
%% against only ONE topic-partition.
-spec parse_response(rsp()) -> term().
parse_response(Rsp) -> kpro_rsp_lib:parse(Rsp).

%% @doc Encode request to byte stream.
-spec encode_request(client_id(), corr_id(), req()) -> iodata().
encode_request(ClientId, CorrId, Req) ->
  kpro_req_lib:encode(ClientId, CorrId, Req).

%% @doc The messageset is not decoded upon receiving (in socket process).
%% Pass the message set as binary to the consumer process and decode there.
%% Return `?incomplete_batch(ExpectedSize)' if the fetch size is not big
%% enough for even one single message. Otherwise return `[{Meta, Messages}]'
%% where `Meta' is either `?KPRO_NO_BATCH_META' for magic-version 0-1 or
%% `kpro:batch_meta()' for magic-version 2 or above.
-spec decode_batches(binary()) -> kpro:batch_decode_result().
decode_batches(<<_:64/?INT, L:32, T/binary>> = Bin) when size(T) >= L ->
  kpro_batch:decode(Bin);
decode_batches(<<_:64/?INT, L:32, _T/binary>>) ->
  %% not enough to decode one single message for magic v0-1
  ?incomplete_batch(L + ?BATCH_LEADING_BYTES);
decode_batches(_) ->
  %% not enough to even get the size header
  ?incomplete_batch(?BATCH_LEADING_BYTES).

%% @doc Send a request, wait for response.
%% Immediately return 'ok' if it is a produce request with `required_acks = 0'.
-spec request_sync(pid(), req(), timeout()) ->
        ok | {ok, rsp()} | {error, any()}.
request_sync(ConnectionPid, Request, Timeout) ->
  kpro_connection:request_sync(ConnectionPid, Request, Timeout).

%% @doc Send a request and get back a correlation ID to match future response.
%% Immediately return 'ok' if it is a produce request with `required_acks = 0'.
-spec request_async(pid(), req()) ->
        ok | {ok, corr_id()} | {error, any()}.
request_async(ConnectionPid, Request) ->
  kpro_connection:request_async(ConnectionPid, Request).

%% @doc Connect to any of the endpoints in the given list.
%% NOTE: Connection process is linked to caller unless `nolink => true'
%%       is set in connection config
-spec connect_any([endpoint()], conn_config()) ->
        {ok, connection()} | {error, any()}.
connect_any(Endpoints, ConnConfig) ->
  kpro_brokers:connect_any(Endpoints, ConnConfig).

%% @doc Sotp connection process.
-spec close_connection(connection()) -> ok.
close_connection(Connection) ->
  kpro_connection:stop(Connection).

%% @doc Connect partition leader.
%% If the fist arg is not an already established metadata connection
%% but a bootstrapping endpoint list, this function will first try to
%% establish a temp connection to any of the bootstrapping endpoints.
%% Then send metadata request to discover partition leader broker
%% Finally connect to the leader broker.
%% NOTE: Connection process is linked to caller unless `nolink => true'
%%       is set in connection config.
-spec connect_partition_leader(connection() | [endpoint()], conn_config(),
                               topic(), partition()) ->
        {ok, connection()} | {error, any()}.
connect_partition_leader(Bootstrap, ConnConfig, Topic, Partition) ->
  connect_partition_leader(Bootstrap, ConnConfig, Topic, Partition, #{}).

%% @doc Connect partition leader.
-spec connect_partition_leader(connection() | [endpoint()], conn_config(),
                               topic(), partition(), #{timeout => timeout()}) ->
        {ok, connection()} | {error, any()}.
connect_partition_leader(Bootstrap, ConnConfig, Topic, Partition, Opts) ->
  kpro_brokers:connect_partition_leader(Bootstrap, ConnConfig,
                                        Topic, Partition, Opts).

%% @doc Discover partition leader broker endpoint.
%% An implicit step performed in `connect_partition_leader'.
%% This is useful when the caller wants to re-use already established
%% towards the discovered endpoint.
-spec discover_partition_leader(connection(), topic(),partition(),
                                timeout()) -> {ok, endpoint()} | {error, any()}.
discover_partition_leader(Connection, Topic, Partition, Timeout) ->
  kpro_brokers:discover_partition_leader(Connection, Topic, Partition, Timeout).

%% @see connect_controller/3.
-spec connect_controller(connection() | [endpoint()], conn_config()) ->
        {ok, connection()} | {error, any()}.
connect_controller(Bootstrap, ConnConfig) ->
  connect_controller(Bootstrap, ConnConfig, #{}).

%% @doc Connect to the controller broker of the kafka cluster.
-spec connect_controller(connection() | [endpoint()], conn_config(),
                         #{timeout => timeout()}) ->
        {ok, connection()} | {error, any()}.
connect_controller(Bootstrap, ConnConfig, Opts) ->
  kpro_brokers:connect_controller(Bootstrap, ConnConfig, Opts).

%% @doc Connect to group or transaction coordinator.
%% If the first arg is not a connection pid but a list of bootstrapping
%% endpoints, it will frist try to connect to any of the nodes
%% NOTE: 'txn' type only applicable to kafka 0.11 or later
-spec connect_coordinator(connection() | [endpoint()], conn_config(),
                          #{ type => coordinator_type()
                           , id => binary()
                           , timeout => timeout()
                           }) -> {ok, connection()} | {error, any()}.
connect_coordinator(Bootstrap, ConnConfig, Args) ->
  kpro_brokers:connect_coordinator(Bootstrap, ConnConfig, Args).

%% @doc Discover group or transactional coordinator.
%% An implicit step performed in `connect_coordinator'.
%% This is useful when the caller wants to re-use already established
%% towards the discovered endpoint.
-spec discover_coordinator(connection(), coordinator_type(),
                           group_id() | transactional_id(), timeout()) ->
        {ok, endpoint()} | {error, any()}.
discover_coordinator(Connection, Type, Id, Timeout) ->
  kpro_brokers:discover_coordinator(Connection, Type, Id, Timeout).

%% @doc Qury API versions using the given `kpro_connection' pid.
-spec get_api_versions(connection()) ->
        {ok, vsn_ranges()} | {error, any()}.
get_api_versions(Connection) ->
  kpro_brokers:get_api_versions(Connection).

%% @doc Get version range for the given API.
-spec get_api_vsn_range(connection(), api()) ->
        {ok, vsn_range()} | {error, any()}.
get_api_vsn_range(Connection, API) ->
  kpro_brokers:get_api_vsn_range(Connection, API).

%% @see kpro_lib:find/2.
-spec find(field_name(), struct()) -> field_value().
find(Field, Struct) -> kpro_lib:find(Field, Struct).

%% @see kpro_lib:find/3
-spec find(field_name(), struct(), field_value()) -> field_value().
find(Field, Struct, Default) -> kpro_lib:find(Field, Struct, Default).

%%%_* Transactional APIs =======================================================

%% @doc Initialize a transaction context, the connection should be established
%% towards transactional coordinator broker.
%% By default the request timeout `timeout' is 5 seconds. This is for client
%% to abort waiting for response and consider it an error `{error, timeout}'.
%% Transaction timeout `txn_timeout' is `-1' by default, which means use kafka
%% broker setting. The default timeout in kafka broker is 1 minute.
%% `txn_timeout' is for kafka transaction coordinator to abort transaction if
%% a transaction did not end (commit or abort) in time.
-spec txn_init_ctx(connection(), transactional_id()) ->
        {ok, txn_ctx()} | {error, any()}.
txn_init_ctx(Connection, TxnId) ->
  txn_init_ctx(Connection, TxnId, #{}).

%% @doc Initialize a transaction context, the connection should be established
%% towards transactional coordinator broker.
-spec txn_init_ctx(connection(), transactional_id(),
                   #{ timeout => timeout()
                    , txn_timeout => pos_integer()
                    }) -> {ok, txn_ctx()} | {error, any()}.
txn_init_ctx(Connection, TxnId, Opts) ->
  kpro_txn_lib:txn_init_ctx(Connection, TxnId, Opts).

%% @doc Abort transaction.
-spec txn_abort(txn_ctx()) -> ok | {errory, any()}.
txn_abort(TxnCtx) ->
  txn_abort(TxnCtx, #{}).

%% @doc Abort transaction.
-spec txn_abort(txn_ctx(), #{timeout => timeout()}) -> ok | {error, any()}.
txn_abort(TxnCtx, Opts) ->
  kpro_txn_lib:end_txn(TxnCtx, abort, Opts).

%% @see txn_send_partitions/3
-spec txn_send_partitions(txn_ctx(), [{topic(), partition()}]) ->
        ok | {error, any()}.
txn_send_partitions(TxnCtx, TPL) ->
  txn_send_partitions(TxnCtx, TPL, #{}).

%% @doc Add partitions to transaction.
-spec txn_send_partitions(txn_ctx(), [{topic(), partition()}],
                          #{timeout => timeout()}) -> ok | {error, any()}.
txn_send_partitions(TxnCtx, TPL, Opts) ->
  kpro_txn_lib:add_partitions_to_txn(TxnCtx, TPL, Opts).

%% @doc see txn_offset_commit/5
-spec txn_offset_commit(connection(), group_id(), txn_ctx(),
                        offsets_to_commit()) -> ok | {error, any()}.
txn_offset_commit(GrpConnection, GrpId, TxnCtx, Offsets) ->
  txn_offset_commit(GrpConnection, GrpId, TxnCtx, Offsets, #{}).

%% @doc Send transactional offset commit request to group coordinator.
%% `user_data' in `Opts' is used as default user-data in offset commit request
%% if there is no user-data associated with offset in `offsets_to_commit()'
-spec txn_offset_commit(connection(), group_id(), txn_ctx(),
                        offsets_to_commit(),
                        #{timeout => timeout(),
                          user_data => binary()}) -> ok | {error, any()}.
txn_offset_commit(GrpConnection, GrpId, TxnCtx, Offsets, Opts) ->
  kpro_txn_lib:txn_offset_commit(GrpConnection, GrpId, TxnCtx, Offsets, Opts).

%% @see txn_send_cg/3
txn_send_cg(TxnCtx, CgId) ->
  txn_send_cg(TxnCtx, CgId, #{}).

%% @doc Add consumed offsets to transaction.
%% This is done by sending the consumer group ID to transaction coordinator.
-spec txn_send_cg(txn_ctx(), group_id(), #{timeout => timeout()}) ->
        ok | {error, any()}.
txn_send_cg(TxCtx, CgId, Opts) ->
  kpro_txn_lib:add_offsets_to_txn(TxCtx, CgId, Opts).

%% @doc Commit transaction.
-spec txn_commit(txn_ctx()) -> ok | {error, any()}.
txn_commit(TxnCtx) ->
  txn_commit(TxnCtx, #{}).

%% @doc Commit transaction.
-spec txn_commit(txn_ctx(), #{timeout => timeout()}) -> ok | {error, any()}.
txn_commit(TxnCtx, Opts) ->
  kpro_txn_lib:end_txn(TxnCtx, commit, Opts).

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
