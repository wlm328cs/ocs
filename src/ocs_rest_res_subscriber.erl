%%% ocs_rest_res_subscriber.erl
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @copyright 2016 - 2017 SigScale Global Inc.
%%% @end
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc This library module implements resource handling functions
%%% 	for a REST server in the {@link //ocs. ocs} application.
%%%
-module(ocs_rest_res_subscriber).
-copyright('Copyright (c) 2016 - 2017 SigScale Global Inc.').

-export([content_types_accepted/0, content_types_provided/0,
		get_subscribers/1, get_subscriber/2, post_subscriber/1,
		patch_subscriber/4, delete_subscriber/1]).

-include_lib("radius/include/radius.hrl").
-include("ocs.hrl").

-spec content_types_accepted() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations accepted.
content_types_accepted() ->
	["application/json", "application/json-patch+json"].

-spec content_types_provided() -> ContentTypes
	when
		ContentTypes :: list().
%% @doc Provides list of resource representations available.
content_types_provided() ->
	["application/json"].

-spec get_subscriber(Id, Query) -> Result
	when
		Id :: string(),
		Query :: [{Key :: string(), Value :: string()}],
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()}.
%% @doc Body producing function for `GET /ocs/v1/subscriber/{id}'
%% requests.
get_subscriber(Id, Query) ->
	case lists:keytake("fields", 1, Query) of
		{value, {_, L}, NewQuery} ->
			get_subscriber(Id, NewQuery, string:tokens(L, ","));
		false ->
			get_subscriber(Id, Query, [])
	end.
%% @hidden
get_subscriber(Id, [] = _Query, Filters) ->
	get_subscriber1(Id, Filters);
get_subscriber(_Id, _Query, _Filters) ->
	{error, 400}.
%% @hidden
get_subscriber1(Id, Filters) ->
	case ocs:find_subscriber(Id) of
		{ok, #subscriber{password = PWBin, attributes = Attributes,
				buckets = Buckets, enabled = Enabled,
				multisession = Multi, last_modified = LM}} ->
			Etag = etag(LM),
			Att = radius_to_json(Attributes),
			Att1 = {array, Att},
			Password = binary_to_list(PWBin),
			RespObj1 = [{"id", Id}, {"href", "/ocs/v1/subscriber/" ++ Id}],
			RespObj2 = [{"attributes", Att1}],
			RespObj3 = case Filters == []
				orelse lists:keymember("password", 1, Filters) of
					true ->
						[{"password", Password}];
					false ->
						[]
				end,
			RespObj4 = case Filters == []
				orelse lists:keymember("totalBalance", 1, Filters) of
					true ->
						AccBalance = accumulated_balance(Buckets),
						[{"totalBalance", AccBalance}];
					false ->
						[]
				end,
			RespObj5 = case Filters == []
				orelse lists:keymember("enabled", 1, Filters) of
					true ->
						[{"enabled", Enabled}];
					false ->
						[]
				end,
			RespObj6 = case Filters == []
				orelse lists:keymember("multisession", 1, Filters) of
					true ->
						[{"multisession", Multi}];
					false ->
						[]
				end,
			JsonObj  = {struct, RespObj1 ++ RespObj2 ++ RespObj3
					++ RespObj4 ++ RespObj5 ++ RespObj6},
			Body = mochijson:encode(JsonObj),
			Headers = [{content_type, "application/json"}, {etag, Etag}],
			{ok, Headers, Body};
		{error, not_found} ->
			{error, 404}
	end.

-spec get_subscribers(Query) -> Result
	when
		Query :: [{Key :: string(), Value :: string()}],
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()}.
%% @doc Body producing function for `GET /ocs/v1/subscriber'
%% requests.
get_subscribers(Query) ->
	case ocs:get_subscribers() of
		{error, _} ->
			{error, 404};
		Subscribers ->
			case lists:keytake("fields", 1, Query) of
				{value, {_, L}, NewQuery} ->
					get_subscribers(Subscribers, NewQuery, string:tokens(L, ","));
				false ->
					get_subscribers(Subscribers, Query, [])
			end
	end.
%% @hidden
get_subscribers(Subscribers, Query, Filters) ->
	try
		case lists:keytake("sort", 1, Query) of
			{value, {_, "id"}, NewQuery} ->
				{lists:keysort(#subscriber.name, Subscribers), NewQuery};
			{value, {_, "-id"}, NewQuery} ->
				{lists:reverse(lists:keysort(#subscriber.name, Subscribers)), NewQuery};
			{value, {_, "password"}, NewQuery} ->
				{lists:keysort(#subscriber.password, Subscribers), NewQuery};
			{value, {_, "-password"}, NewQuery} ->
				{lists:reverse(lists:keysort(#subscriber.password, Subscribers)), NewQuery};
			{value, {_, "totalBalance"}, NewQuery} ->
				{lists:keysort(#subscriber.buckets, Subscribers), NewQuery};
			{value, {_, "-totalBalance"}, NewQuery} ->
				{lists:reverse(lists:keysort(#subscriber.buckets, Subscribers)), NewQuery};
			{value, {_, "enabled"}, NewQuery} ->
				{lists:keysort(#subscriber.enabled, Subscribers), NewQuery};
			{value, {_, "-enabled"}, NewQuery} ->
				{lists:reverse(lists:keysort(#subscriber.enabled, Subscribers)), NewQuery};
			{value, {_, "multisession"}, NewQuery} ->
				{lists:keysort(#subscriber.multisession, Subscribers), NewQuery};
			{value, {_, "-multisession"}, NewQuery} ->
				{lists:reverse(lists:keysort(#subscriber.multisession, Subscribers)), NewQuery};
			false ->
				{Subscribers, Query};
			_ ->
				throw(400)
		end
	of
		{SortedSubscribers, NextQuery} ->
			get_subscribers1(SortedSubscribers, NextQuery, Filters)
	catch
		throw:400 ->
			{error, 400}
	end.
%% @hidden
get_subscribers1(Subscribers, Query, Filters) ->
	{Id, Query1} = case lists:keytake("id", 1, Query) of
		{value, {_, V1}, Q1} ->
			{V1, Q1};
		false ->
			{[], Query}
	end,
	{Password, Query2} = case lists:keytake("password", 1, Query1) of
		{value, {_, V2}, Q2} ->
			{V2, Q2};
		false ->
			{[], Query1}
	end,
	{Balance, Query3} = case lists:keytake("totalBalance", 1, Query2) of
		{value, {_, V3}, Q3} ->
			{V3, Q3};
		false ->
			{[], Query2}
	end,
	{Enabled, Query4} = case lists:keytake("enabled", 1, Query3) of
		{value, {_, V4}, Q4} ->
			{V4, Q4};
		false ->
			{[], Query3}
	end,
	{Multi, Query5} = case lists:keytake("multisession", 1, Query4) of
		{value, {_, V5}, Q5} ->
			{V5, Q5};
		false ->
			{[], Query4}
	end,
	get_subscribers2(Subscribers, Id, Password, Balance, Enabled, Multi, Query5, Filters).
%% @hidden
get_subscribers2(Subscribers, Id, Password, Balance, Enabled, Multi, [] = _Query, Filters) ->
	F = fun(#subscriber{name = Na, password = Pa, attributes = Attributes, 
			buckets = Bu, enabled = Ena, multisession = Mul}) ->
		Nalist = binary_to_list(Na),
		T1 = lists:prefix(Id, Nalist),
		Palist = binary_to_list(Pa),
		T2 = lists:prefix(Password, Palist),
		Att = radius_to_json(Attributes),
		Att1 = {array, Att},
		T3 = lists:prefix(Balance, Bu),
		T4 = lists:prefix(Enabled, [Ena]),
		T5 = lists:prefix(Multi, [Mul]),
		if
			T1 and T2 and T3 and T4 and T5->
				RespObj1 = [{"id", Nalist}, {"href", "/ocs/v1/subscriber/" ++ Nalist}],
				RespObj2 = [{"attributes", Att1}],
				RespObj3 = case Filters == []
						orelse lists:keymember("password", 1, Filters) of
					true ->
						[{"password", Palist}];
					false ->
						[]
				end,
				RespObj4 = case Filters == []
						orelse lists:keymember("totalBalance", 1, Filters) of
					true ->
						AccBalance = accumulated_balance(Bu),
						[{"totalBalance", AccBalance}];
					false ->
						[]
				end,
				RespObj5 = case Filters == []
						orelse lists:keymember("enabled", 1, Filters) of
					true ->
						[{"enabled", Ena}];
					false ->
						[]
				end,
				RespObj6 = case Filters == []
						orelse lists:keymember("multisession", 1, Filters) of
					true ->
						[{"multisession", Mul}];
					false ->
						[]
				end,
				{true, {struct, RespObj1 ++ RespObj2 ++ RespObj3
							++ RespObj4 ++ RespObj5 ++ RespObj6}};
			true ->
				false
		end
	end,
	try
		JsonObj = lists:filtermap(F, Subscribers),
		Size = integer_to_list(length(JsonObj)),
		ContentRange = "item 1-" ++ Size ++ "/" ++ Size,
		Body  = mochijson:encode({array, lists:reverse(JsonObj)}),
		{ok, [{content_type, "application/json"},
				{content_range, ContentRange}], Body}
	catch
		_:_Reason ->
			{error, 500}
	end;
get_subscribers2(_, _, _, _, _, _, _, _) ->
	{error, 400}.

-spec post_subscriber(RequestBody) -> Result 
	when 
		RequestBody :: list(),
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()}.
%% @doc Respond to `POST /ocs/v1/subscriber' and add a new `subscriber'
%% resource.
post_subscriber(RequestBody) ->
	try 
		{struct, Object} = mochijson:decode(RequestBody),
		IdIn = case lists:keyfind("id", 1, Object) of
			{"id", ID} ->
				ID;
			false ->
				undefined
		end,
		PasswordIn = case lists:keyfind("password", 1, Object) of
			{"password", Pass} ->
				Pass;
			false ->
				undefined
		end,
		Attributes = case lists:keyfind("attributes", 1, Object) of
			{_, {array, JsonObjList}} ->
				json_to_radius(JsonObjList);
			false ->
				[]
		end,
		{Buckets, BucketRef} = case lists:keyfind("buckets", 1, Object) of
			{"buckets", {array, BktStruct}} ->
				F = fun({struct, Bucket}, AccIn) ->
					{_, Amount} = lists:keyfind("amount", 1, Bucket),
					{_, Units} = lists:keyfind("units", 1, Bucket),
					BucketType = bucket_type(Units),
					_Product = proplists:get_value("product", Bucket, ""),
					BR = #bucket{bucket_type = BucketType, remain_amount =
						#remain_amount{unit = Units, amount = Amount}},
					[BR | AccIn]
				end,
				{lists:reverse(lists:foldl(F, [], BktStruct)), {array, BktStruct}};
			false ->
				undefined
		end,
		Enabled = case lists:keyfind("enabled", 1, Object) of
			{_, En} ->
				En;
			false ->
				undefined
		end,
		Multi = case lists:keyfind("multisession", 1, Object) of
			{_, Mu} ->
				Mu;
			false ->
				undefined
		end,
		case ocs:add_subscriber(IdIn, PasswordIn, Attributes, Buckets, Enabled, Multi) of
			{ok, #subscriber{name = IdOut, last_modified = LM} = S} ->
				Id = binary_to_list(IdOut),
				Location = "/ocs/v1/subscriber/" ++ Id,
				JAttributes = {array, radius_to_json(S#subscriber.attributes)},
				RespObj = [{id, Id}, {href, Location},
						{password, binary_to_list(S#subscriber.password)},
						{attributes, JAttributes}, {buckets, BucketRef},
						{enabled, S#subscriber.enabled},
						{multisession, S#subscriber.multisession}],
				JsonObj  = {struct, RespObj},
				Body = mochijson:encode(JsonObj),
				Headers = [{location, Location}, {etag, etag(LM)}],
				{ok, Headers, Body};
			{error, _} ->
				{error, 400}
		end
	catch
		_:_ ->
			{error, 400}
	end.

-spec patch_subscriber(Id, Etag, ContenType, ReqBody) -> Result
	when
		Id :: string(),
		Etag :: undefined | list(),
		ContenType :: string(),
		ReqBody :: list(),
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()} .
%% @doc	Respond to `PATCH /ocs/v1/subscriber/{id}' request and
%% Updates a existing `subscriber''s password or attributes. 
patch_subscriber(Id, undefined, CType, ReqBody) ->
	patch_subscriber1(Id, undefined, CType, ReqBody);
patch_subscriber(Id, Etag, CType, ReqBody) ->
	try
		Etag1 = etag(Etag),
		patch_subscriber1(Id, Etag1, CType, ReqBody)
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
patch_subscriber1(Id, Etag, "application/json", ReqBody) ->
	case ocs:find_subscriber(Id) of
		{ok, #subscriber{password = CurrPassword, attributes = CurrAttr,
				buckets = Bal, enabled = Enabled,
				multisession = Multi, last_modified = CurrentEtag}}
				when Etag == CurrentEtag; Etag == undefined ->
			try
				{struct, Object} = mochijson:decode(ReqBody),
				{_, Type} = lists:keyfind("update", 1, Object),
				{Password, RadAttr, NewEnabled, NewMulti} = case Type of
					"attributes" ->
						{_, {array, AttrJs}} = lists:keyfind("attributes", 1, Object),
						NewAttributes = json_to_radius(AttrJs),
						{_, Balance} = lists:keyfind("balance", 1, Object),
						{_, EnabledStatus} = lists:keyfind("enabled", 1, Object),
						{_, MultiSession} = lists:keyfind("multisession", 1, Object),
						ocs:update_attributes(Id, Balance, NewAttributes, EnabledStatus, MultiSession),
						{CurrPassword, NewAttributes, EnabledStatus, MultiSession};
					"password" ->
						{_, NewPassword } = lists:keyfind("newpassword", 1, Object),
						ocs:update_password(Id, NewPassword),
						{NewPassword, CurrAttr, Enabled, Multi}
				end,
				patch_subscriber2(Id, Etag, Password, RadAttr, Bal, NewEnabled, NewMulti)
			catch
				_:_ ->
					{error, 400}
			end;
		{ok,  _} ->
			{error, 412};
		{error, _} ->
			{error, 404}
	end;
patch_subscriber1(Id, Etag, "application/json-patch+json", ReqBody) ->
	try
		{array, OpList} = mochijson:decode(ReqBody),
		ValidOpList = validated_operations(OpList),
		case execute_json_patch_operations(Id, Etag, ValidOpList) of
			{ok, #subscriber{password = Password,
					attributes = RadAttr, buckets = Buckets,
					enabled = Enabled, multisession = MSession}} ->
				Attributes = {array, radius_to_json(RadAttr)},
				TotalBalance = accumulated_balance(Buckets),
				RespObj =[{id, Id}, {href, "/ocs/v1/subscriber/" ++ Id},
				{password, Password}, {attributes, Attributes},
				{totalBalance, TotalBalance}, {enabled, Enabled}, {multisession, MSession}],
				JsonObj  = {struct, RespObj},
				RespBody = mochijson:encode(JsonObj),
				Headers = case Etag of
					undefined ->
						[];
					_ ->
						[{etag, etag(Etag)}]
				end,
				{ok, Headers, RespBody};
			{error, Status} ->
				{error, Status}
		end
	catch
		_:_ ->
			{error, 400}
	end.
%% @hidden
patch_subscriber2(Id, Etag, Password, RadAttr, Balance, Enabled, Multi) ->
	Attributes = {array, radius_to_json(RadAttr)},
	RespObj =[{id, Id}, {href, "/ocs/v1/subscriber/" ++ Id},
		{password, Password}, {attributes, Attributes}, {balance, Balance},
		{enabled, Enabled}, {multisession, Multi}],
	JsonObj  = {struct, RespObj},
	RespBody = mochijson:encode(JsonObj),
	Headers = case Etag of
		undefined ->
			[];
		_ ->
			[{etag, etag(Etag)}]
	end,
	{ok, Headers, RespBody}.

-spec delete_subscriber(Id) -> Result
	when
		Id :: string(),
		Result :: {ok, Headers :: [tuple()], Body :: iolist()}
				| {error, ErrorCode :: integer()} .
%% @doc Respond to `DELETE /ocs/v1/subscriber/{id}' request and deletes
%% a `subscriber' resource. If the deletion is succeeded return true.
delete_subscriber(Id) ->
	ok = ocs:delete_subscriber(Id),
	{ok, [], []}.

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @hidden
json_to_radius(JsonObjList) ->
	json_to_radius(JsonObjList, []).
%% @hidden
json_to_radius([{struct, [{"name", "ascendDataRate"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T,Acc);
json_to_radius([{struct, [{"name", "ascendDataRate"}, {"value", V}]} | T], Acc) ->
	Attribute = {?VendorSpecific, {?Ascend, {?AscendDataRate, V}}},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct, [{"name", "ascendXmitRate"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T,Acc);
json_to_radius([{struct, [{"name", "ascendXmitRate"}, {"value", V}]} | T], Acc) ->
	Attribute = {?VendorSpecific, {?Ascend, {?AscendXmitRate, V}}},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct,[{"name","sessionTimeout"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T, Acc);
json_to_radius([{struct,[{"name","sessionTimeout"}, {"value", V}]} | T], Acc) ->
	Attribute = {?SessionTimeout, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct,[{"name","acctInterimInterval"}, {"value", V}]} | T], Acc) when V == null; V == ""->
	json_to_radius(T,Acc);
json_to_radius([{struct,[{"name","acctInterimInterval"}, {"value", V}]} | T], Acc) ->
	Attribute = {?AcctInterimInterval, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct,[{"name","class"}, {"value", V}]} | T], Acc) when V == null; V == "" ->
	json_to_radius(T, Acc);
json_to_radius([{struct,[{"name","class"}, {"value", V}]} | T], Acc) ->
	Attribute = {?Class, V},
	json_to_radius(T, [Attribute | Acc]);
json_to_radius([{struct, [{"name", "vendorSpecific"} | VendorSpecific]} | T], Acc) ->
	case vendor_specific(VendorSpecific) of
		[] ->
			json_to_radius(T, Acc);
		Attribute ->
			json_to_radius(T, [Attribute | Acc])
	end;
json_to_radius([], Acc) ->
	Acc.

%% @hidden
radius_to_json(RadiusAttributes) ->
	radius_to_json(RadiusAttributes, []).
%% @hidden
radius_to_json([{?SessionTimeout, V} | T], Acc) ->
	Attribute = {struct, [{"name", "sessionTimeout"}, {"value",  V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?AcctInterimInterval, V} | T], Acc) ->
	Attribute = {struct, [{"name", "acctInterimInterval"}, {"value", V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?Class, V} | T], Acc) ->
	Attribute = {struct, [{"name", "class"}, {"value", V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?VendorSpecific, {?Ascend, {?AscendDataRate, V}}} | T], Acc) ->
	Attribute = {struct, [{"name", "ascendDataRate"}, {"value",  V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?VendorSpecific, {?Ascend, {?AscendXmitRate, V}}} | T], Acc) ->
	Attribute = {struct, [{"name", "ascendXmitRate"}, {"value",  V}]},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([{?VendorSpecific, _} = H | T], Acc) ->
	Attribute = {struct, vendor_specific(H)},
	radius_to_json(T, [Attribute | Acc]);
radius_to_json([_| T], Acc) ->
	radius_to_json(T, Acc);
radius_to_json([], Acc) ->
	Acc.

%% @hidden
vendor_specific(AttrJson) when is_list(AttrJson) ->
	{_, Type} = lists:keyfind("type", 1, AttrJson),
	{_, VendorID} = lists:keyfind("vendorId", 1, AttrJson),
	{_, Key} = lists:keyfind("vendorType", 1, AttrJson),
	case lists:keyfind("value", 1, AttrJson) of
		{_, null} ->
			[];
		{_, Value} ->
			{Type, {VendorID, {Key, Value}}}
	end;
vendor_specific({?VendorSpecific, {VendorID, {VendorType, Value}}}) ->
	AttrObj = [{"name", vendorSpecific},
				{"vendorId", VendorID},
				{"vendorType", VendorType},
				{"value", Value}],
	{struct, AttrObj}.

-spec etag(V1) -> V2
	when
		V1 :: string() | {N1, N2},
		V2 :: {N1, N2} | string(),
		N1 :: integer(),
		N2 :: integer().
%% @doc Generate a tuple with 2 integers from Etag string
%% value or vice versa.
%% @hidden
etag(V) when is_list(V) ->
	[TS, N] = string:tokens(V, "-"),
	{list_to_integer(TS), list_to_integer(N)};
etag(V) when is_tuple(V) ->
	{TS, N} = V,
	integer_to_list(TS) ++ "-" ++ integer_to_list(N).

%% @hidden
-spec validated_operations(UnOrderAttributes) -> OrderedAtttibutes
	when
		UnOrderAttributes :: [{struct, [tuple()]}],
		OrderedAtttibutes :: [tuple()].
%% @doc Processes scrambled json attributes (with regard to
%% https://tools.ietf.org/html/rfc6902#section-3) and return
%% a list of key, value tuples.
validated_operations(UAttr) ->
	F = fun(F, [{struct, Op} | T],  Acc) ->
			{_, "replace"} = lists:keyfind("op", 1, Op),
			{_, P} = lists:keyfind("path", 1, Op),
			{_, V} = lists:keyfind("value", 1, Op),
			[P1] = string:tokens(P, "/"),
			F(F, T, [{P1, V} | Acc]);
		(_, [], Acc) ->
			lists:reverse(Acc)
	end,
	F(F, UAttr, []).

-spec execute_json_patch_operations(Id, Etag, OpList) ->
		{ok, Subscriber} | {error, Status} when
	Id :: string(),
	Etag :: undefined | tuple(),
	OpList :: [tuple()],
	Subscriber :: #subscriber{},
	Status :: 412 | 404 | 500.
%% @doc Execute json-patch opearations and return subscriber record
%% @private
execute_json_patch_operations(Id, Etag, OpList) ->
	try
		Password = proplists:get_value("password", OpList, undefined),
		Attributes = case lists:keyfind("attributes", 1, OpList) of
			{_, {array, JsonAttr}} ->
				json_to_radius(JsonAttr);
			false ->
				undefined
		end,
		Buckets = case lists:keyfind("buckets", 1, OpList) of
			{_, {array, BucketObjs}} ->
				F = fun({strcut, Bucket}, AccIn) ->
						{_, Amount} = lists:keyfind("amount", 1, Bucket),
						{_, Units} = lists:keyfind("units", 1, Bucket),
						_Product = proplists:get_value("product", Bucket, ""),
						B = #bucket{remain_amount =
							#remain_amount{amount = Amount, unit = Units}},
						[B | AccIn]
				end,
				AccOut = lists:foldl(F, [], BucketObjs),
				lists:reverse(AccOut);
			false ->
				undefined
		end,
		Enabled = proplists:get_value("enabled", OpList, undefined),
		MultiSession = proplists:get_value("multisession", OpList, undefined),
		case update_subscriber(Id, Password,
				Attributes, Buckets, Enabled, MultiSession, Etag) of
			{ok, Subscriber} ->
				{ok, Subscriber};
			{error, not_found} ->
				{error, 404};
			{error, precondition_faild} ->
				{error, 412};
			{error, _Reason} ->
				{error, 500}
		end
	catch
		_:_ ->
			{error, 400}
	end.

-spec validate_operation(Operation) -> Result
	when
		Operation	:: [tuple()],
		Result		:: {Op, Path, Value} | {error, StatusCode},
		Op				:: string(),
		Path			:: string(),
		Value			:: string() | tuple(),
		StatusCode	:: 400.
%% @doc validate elements in an operation object and return
%% `op', `path' and `value' or error status code.
validate_operation(Operation) ->
	OpT = lists:keyfind("op", 1, Operation),
	PathT = lists:keyfind("path", 1, Operation),
	ValueT = lists:keyfind("value", 1, Operation),
	case {OpT, PathT, ValueT} of
		{{_, Op}, {_, Path}, {_, Value}} ->
			{Op, Path, Value};
		_ ->
			{error, 400}
	end.

-spec accumulated_balance(Buckets) ->	AccumulatedBalance
	when
		Buckets					:: [#bucket{}],
		AccumulatedBalance	:: tuple().
%% @doc return accumulated buckets as a json object.
accumulated_balance([]) ->
	[];
accumulated_balance(Buckets) ->
	accumulated_balance1(Buckets, []).
%% @hidden
accumulated_balance1([Bucket | T], AccBalance) ->
	AB = accumulated_balance2(T, accumulated_balance2(Bucket, AccBalance)),
	F = fun({octets, {U1, A1}}, AccIn) ->
				Obj = {struct, [{"amount", A1}, {"units", U1}]},
				[Obj | AccIn];
			({cents, {U2, A2}}, AccIn) ->
				Obj = {struct, [{"amount", A2}, {"units", U2}]},
				[Obj | AccIn];
			({seconds, {U3, A3}}, AccIn) ->
				Obj = {struct, [{"amount", A3}, {"units", U3}]},
				[Obj | AccIn]
	end,
	JsonArray = lists:reverse(lists:foldl(F, [], AB)),
	{array, JsonArray}.
%% @hidden
accumulated_balance2(#bucket{bucket_type = octets, remain_amount =
		#remain_amount{unit = Units, amount = Amount}}, AccBalance) ->
	accumulated_balance3(octets, Units, Amount, AccBalance);
accumulated_balance2(#bucket{bucket_type = cents, remain_amount =
		#remain_amount{unit = Units, amount = Amount}}, AccBalance) ->
	accumulated_balance3(cents, Units, Amount, AccBalance);
accumulated_balance2(#bucket{bucket_type = seconds, remain_amount =
		#remain_amount{unit = Units, amount = Amount}}, AccBalance) ->
	accumulated_balance3(seconds, Units, Amount, AccBalance);
accumulated_balance2([], AccBalance) ->
	AccBalance.
%% @hidden
accumulated_balance3(Key, Units, Amount, AccBalance) ->
	case lists:keytake(Key, 1, AccBalance) of
		{value, {Key, {Units, Balance}}, Rest} ->
			[{Key, {Units, Amount + Balance}} | Rest];
		false ->
			[{Key, {Units, Amount}} | AccBalance]
	end.

-spec bucket_type(SBucketType) -> BucketType
	when
		SBucketType	:: string(),
		BucketType	:: octets | cents | seconds.
%% @doc return the bucket type.
bucket_type(BucketType) ->
	bucket_type1(string:to_lower(BucketType)).
%% @hidden
bucket_type1("octets") ->
	octets;
bucket_type1("cents") ->
	cents;
bucket_type1("seconds") ->
	seconds.

-spec update_subscriber(Identity, Password, Attributes, Buckets, EnabledStatus, MultiSession, Etag) ->
		Result when
	Identity			:: undefined | string() | binary(),
	Password			:: undefined | string() | binary(),
	Attributes		:: undefined | radius_attributes:attributes(),
	Buckets			:: undefined | [#bucket{}],
	EnabledStatus	:: undefined | boolean(),
	MultiSession	:: undefined | boolean(),
	Etag 				:: undefined | tuple(),
	Result 			:: {ok, Subscriber} | {error, Reason},
	Subscriber		:: #subscriber{},
	Reason			:: not_found | precondition_faild | term().
%% @private
%% @doc update subscriber elements
update_subscriber(Identity, Password, Attributes, Buckets, EnabledStatus, MultiSession, Etag)
		when is_list(Identity) ->
	BIdentity = list_to_binary(Identity),
	update_subscriber(BIdentity, Password, Attributes, Buckets, EnabledStatus, MultiSession, Etag);
update_subscriber(Identity, Password, Attributes, Buckets, EnabledStatus, MultiSession, Etag)
		when is_list(Password) ->
	BPwd = list_to_binary(Password),
	update_subscriber(Identity, BPwd, Attributes, Buckets, EnabledStatus, MultiSession, Etag);
update_subscriber(Identity, Password, Attributes, Buckets, EnabledStatus, MultiSession, Etag) ->
	F = fun() ->
		case mnesia:read(subscriber, Identity, write) of
			[Entry] when
					Entry#subscriber.last_modified == Etag;
					Etag == undefined ->
				NewEntry =
					update_subscriber1(Entry, Password, Attributes, Buckets, EnabledStatus, MultiSession),
				mnesia:write(NewEntry),
				NewEntry;
			[#subscriber{}] ->
				throw(precondition_faild);
			[] ->
				throw(not_found)
		end
	end,
	case mnesia:transaction(F) of
		{atomic, Subscriber} ->
			{ok, Subscriber};
		{aborted, {throw, Reason}} ->
			{error, Reason};
		{aborted, Reason} ->
			{error, Reason}

	end.
%% @hidden
update_subscriber1(Entry, Password, Attributes, Buckets, EnabledStatus, MultiSession) ->
	NewEntry0 = case Password of
		undefined ->
			Entry;
		P ->
			Entry#subscriber{password = P}
	end,
	NewEntry1 = case Attributes of
		undefined ->
			NewEntry0;
		A ->
			NewEntry0#subscriber{attributes = A}
	end,
	NewEntry2 = case Buckets of
		undefined ->
			NewEntry1;
		B ->
			OldBuckets = Entry#subscriber.buckets,
			NewEntry1#subscriber{buckets = [OldBuckets | B]}
	end,
	NewEntry3 = case EnabledStatus of
		undefined ->
			NewEntry2;
		E ->
			NewEntry2#subscriber{enabled = E}
	end,
	NewEntry4 = case MultiSession of
		undefined ->
			NewEntry3;
		M ->
			NewEntry3#subscriber{multisession = M}
	end,
	NewEntry4.
