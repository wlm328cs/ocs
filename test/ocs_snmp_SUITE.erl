%%% ocs_snmp_SUITE.erl
%%% vim: ts=3
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
%%%  @doc Test suite for public API of the {@link //ocs. ocs} application.
%%%
-module(ocs_snmp_SUITE).
-copyright('Copyright (c) 2016 - 2018 SigScale Global Inc.').

%% common_test required callbacks
-export([suite/0, sequences/0, all/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

%%---------------------------------------------------------------------
%%  Test server callback functions
%%---------------------------------------------------------------------

-spec suite() -> DefaultData :: [tuple()].
%% Require variables and set default values for the suite.
%%
suite() ->
	Port = rand:uniform(32767) + 32768,
	[{userdata, [{doc, "Test suite for SNMP agent in SigScale OCS"}]},
	{require, snmp_mgr_agent, snmp},
	{default_config, snmp,
      	[{start_agent, true},
			{agent_udp, Port},
			{agent_engine_id, sigscale_snmp_lib:engine_id()},
			{users,
					[{ocs_mibs_test, [snmpm_user_default, []]}]},
			{managed_agents,
					[{ocs_mibs_test, [ocs_mibs_test, {127,0,0,1}, Port, []]}]}]},
	{timetrap, {minutes, 1}}].

-spec init_per_suite(Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before the whole suite.
%%
init_per_suite(Config) ->
	ok = ocs_test_lib:initialize_db(),
	ok = ocs_test_lib:start(),
	ok = ct_snmp:start(Config, snmp_mgr_agent),
	ok = application:start(sigscale_mibs),
	ok = sigscale_mib:load(),
	DataDir = filename:absname(?config(data_dir, Config)),
	TestDir = filename:dirname(DataDir),
	BuildDir = filename:dirname(TestDir),
	MibDir =  BuildDir ++ "/priv/mibs/",
	ok = ct_snmp:load_mibs([MibDir ++ "SIGSCALE-OCS-MIB"]),
	Config.

-spec end_per_suite(Config :: [tuple()]) -> any().
%% Cleanup after the whole suite.
%%
end_per_suite(Config) ->
	ok = ocs_mib:unload(),
	ok = sigscale_mib:unload(),
	ok = application:stop(sigscale_mibs),
	ok = ct_snmp:stop(Config),
	ok = ocs_test_lib:stop().

-spec init_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> Config :: [tuple()].
%% Initialization before each test case.
%%
init_per_testcase(_TestCase, Config) ->
	Config.

-spec end_per_testcase(TestCase :: atom(), Config :: [tuple()]) -> any().
%% Cleanup after each test case.
%%
end_per_testcase(_TestCase, _Config) ->
	ok.

-spec sequences() -> Sequences :: [{SeqName :: atom(), Testcases :: [atom()]}].
%% Group test cases into a test sequence.
%%
sequences() -> 
	[].

-spec all() -> TestCases :: [Case :: atom()].
%% Returns a list of all test cases in this test suite.
%%
all() -> 
	[get_next_client].

%%---------------------------------------------------------------------
%%  Test cases
%%---------------------------------------------------------------------

get_next_client() ->
	[{userdata, [{doc, "Get next client table"}]}].

get_next_client(Config) ->
	{value, OID} = snmpa:name_to_oid(ocsClientTable),
	{noError, _, _Varbinds} = ct_snmp:get_next_values(ocs_mibs_test,
			[OID], snmp_mgr_agent).

%%---------------------------------------------------------------------
%%  Internal functions
%%---------------------------------------------------------------------

