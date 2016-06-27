-module(dqe_idx_pg).
-behaviour(dqe_idx).

-include("dqe_idx_pg.hrl").

%% API exports
-export([
         init/0,
         lookup/1, lookup/2, lookup_tags/1,
         collections/0, metrics/1, namespaces/1, namespaces/2,
         tags/2, tags/3, values/3, values/4, expand/2,
         add/4, add/5, update/5,
         delete/4, delete/5,
         get_id/4, tdelta/1
        ]).

%%====================================================================
%% API functions
%%====================================================================

init() ->
    Opts = [size, max_overflow, database, username, password],
    Opts1 = [{O, application:get_env(dqe_idx_pg, O, undefined)}
             || O <- Opts],
    {ok, {Host, Port}} = application:get_env(dqe_idx_pg, server),
    pgapp:connect([{host, Host}, {port, Port} | Opts1]).

lookup(Query) ->
    lookup(Query, []).

lookup(Query, Groupings) ->
    {ok, Q, Vs} = query_builder:lookup_query(Query, Groupings),
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:lookup/2] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, Rows}.

lookup_tags(Query) ->
    {ok, Q, Vs} = query_builder:lookup_tags_query(Query),
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:lookup/1] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, Rows}.

collections() ->
    Q = "WITH RECURSIVE t AS ("
        "   SELECT MIN(collection) AS collection FROM " ?MET_TABLE
        "   UNION ALL"
        "   SELECT (SELECT MIN(collection) FROM " ?MET_TABLE
        "     WHERE collection > t.collection)"
        "   FROM t WHERE t.collection IS NOT NULL"
        "   )"
        "SELECT collection FROM t WHERE collection IS NOT NULL",
    Vs = [],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:collections] Query took ~pms: ~s",
                [tdelta(T0), Q]),
    {ok, strip_tpl(Rows)}.

metrics(Collection) when is_binary(Collection) ->
    Q = "SELECT DISTINCT metric FROM "
        ?MET_TABLE
        " WHERE collection = $1",
    Vs = [Collection],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:metrics] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

namespaces(Collection) when is_binary(Collection) ->
    Q = "WITH RECURSIVE t AS ("
        "   SELECT MIN(namespace) AS namespace FROM "
        ?DIM_TABLE
        "     WHERE collection = $1"
        "   UNION ALL"
        "   SELECT (SELECT MIN(namespace) FROM "
        ?DIM_TABLE
        "     WHERE namespace > t.namespace"
        "     AND collection = $1)"
        "   FROM t WHERE t.namespace IS NOT NULL"
        "   )"
        "SELECT namespace FROM t WHERE namespace IS NOT NULL",
    Vs = [Collection],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:namespaces] Query took ~pms: ~s <- ~p",
               [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

namespaces(Collection, Metric) when is_binary(Metric) ->
    namespaces(Collection, dproto:metric_to_list(Metric));

namespaces(Collection, Metric)
  when is_binary(Collection),
       is_list(Metric) ->
    Q = "SELECT DISTINCT(namespace) FROM " ?DIM_TABLE " "
        "LEFT JOIN " ?MET_TABLE " "
        "ON " ?DIM_TABLE ".metric_id = " ?MET_TABLE ".id "
        "WHERE " ?MET_TABLE ".collection = $1 AND " ?MET_TABLE ".metric = $2",
    Vs = [Collection, Metric],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:namespaces] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

tags(Collection, Namespace)
  when is_binary(Collection),
       is_binary(Namespace) ->
    Q = "WITH RECURSIVE t AS ("
        "   SELECT MIN(name) AS name FROM " ?DIM_TABLE
        "     WHERE collection = $1"
        "     AND namespace = $2"
        "   UNION ALL"
        "   SELECT (SELECT MIN(name) FROM " ?DIM_TABLE
        "     WHERE name > t.name"
        "     AND collection = $1"
        "     AND namespace = $2)"
        "   FROM t WHERE t.name IS NOT NULL"
        "   )"
        "SELECT name FROM t WHERE name IS NOT NULL",
    Vs = [Collection, Namespace],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:tags/3] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.
tags(Collection, Metric, Namespace) when is_binary(Metric)->
    tags(Collection, dproto:metric_to_list(Metric), Namespace);

tags(Collection, Metric, Namespace)
  when is_binary(Collection),
       is_list(Metric),
       is_binary(Namespace) ->
    Q = "SELECT DISTINCT(name) FROM " ?DIM_TABLE " "
        "LEFT JOIN " ?MET_TABLE " "
        "ON " ?DIM_TABLE ".metric_id = " ?MET_TABLE ".id "
        "WHERE " ?MET_TABLE ".collection = $1 AND " ?MET_TABLE ".metric = $2 "
        "AND " ?DIM_TABLE ".namespace = $3",
    Vs = [Collection, Metric, Namespace],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:tags/3] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

values(Collection, Namespace, Tag)
  when is_binary(Collection),
       is_binary(Namespace),
       is_binary(Tag) ->
    Q = "SELECT DISTINCT(value) FROM " ?DIM_TABLE " "
        "LEFT JOIN " ?MET_TABLE " "
        "ON " ?DIM_TABLE ".metric_id = " ?MET_TABLE ".id "
        "WHERE " ?MET_TABLE ".collection = $1 "
        "AND " ?DIM_TABLE ".namespace = $2 "
        "AND name = $3",
    Vs = [Collection, Namespace, Tag],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:values/4] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

values(Collection, Metric, Namespace, Tag) when is_binary(Metric)->
    values(Collection, dproto:metric_to_list(Metric), Namespace, Tag);

values(Collection, Metric, Namespace, Tag)
  when is_binary(Collection),
       is_list(Metric),
       is_binary(Namespace),
       is_binary(Tag) ->
    Q = "SELECT DISTINCT(value) FROM " ?DIM_TABLE " "
        "LEFT JOIN " ?MET_TABLE " "
        "ON " ?DIM_TABLE ".metric_id = " ?MET_TABLE ".id "
        "WHERE " ?MET_TABLE ".collection = $1 AND " ?MET_TABLE ".metric = $2 "
        "AND " ?DIM_TABLE ".namespace = $3 AND name = $4",
    Vs = [Collection, Metric, Namespace, Tag],
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:values/4] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    {ok, strip_tpl(Rows)}.

expand(Bucket, Globs) when
      is_binary(Bucket),
      is_list(Globs) ->
    {ok, Q, Vs} = query_builder:glob_query(Bucket, Globs),
    T0 = erlang:system_time(),
    {ok, _Cols, Rows} = pgapp:equery(Q, Vs),
    lager:debug("[dqe_idx:pg:expand/2] Query took ~pms: ~s <- ~p",
                [tdelta(T0), Q, Vs]),
    Rows1 = [K || {K} <- Rows],
    {ok, {Bucket, Rows1}}.

-spec add(Collection::binary(),
          Metric::binary(),
          Bucket::binary(),
          Key::binary()) ->
                 {ok, MetricIdx::non_neg_integer()} |
                 {error, Error::term()}.

add(Collection, Metric, Bucket, Key) ->
    Q = "INSERT INTO " ?MET_TABLE " (collection, metric, bucket, key) VALUES "
        "($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING id",
    Vs = [Collection, Metric, Bucket, Key],
    T0 = erlang:system_time(),
    case pgapp:equery(Q, Vs) of
        %% Returned by DO NOTHING
        {ok, 0} ->
            ok;
        {ok, 1, [_], [{ID}]} ->
            lager:debug("[dqe_idx:pg:add/4] Query too ~pms: ~s <- ~p",
                        [dqe_idx_pg:tdelta(T0), Q, Vs]),

            {ok, ID};
        E ->
            lager:info("[dqe_idx:pg:add/4] Query failed after ~pms: ~s <- ~p",
                       [dqe_idx_pg:tdelta(T0), Q, Vs]),
            E
    end.

add(Collection, Metric, Bucket, Key, []) ->
    add(Collection, Metric, Bucket, Key);

add(Collection, Metric, Bucket, Key, NVs) ->
    case add(Collection, Metric, Bucket, Key) of
        ok ->
            ok;
        {ok, MID} ->
            {Q, Vs} = add_tags(MID, Collection, NVs),
            T0 = erlang:system_time(),
            case pgapp:equery(Q, Vs) of
                {ok, _, _} ->
                    lager:debug("[dqe_idx:pg:add/5] Query too ~pms: ~s <- ~p",
                                [dqe_idx_pg:tdelta(T0), Q, Vs]),
                    {ok, MID};
                E ->
                    lager:info("[dqe_idx:pg:add/5] Query failed after ~pms: "
                               "~s <- ~p", [dqe_idx_pg:tdelta(T0), Q, Vs]),
                    E
            end;
        EAdd ->
            EAdd
    end.

update(Collection, Metric, Bucket, Key, NVs) ->
    AddRes = case add(Collection, Metric, Bucket, Key) of
                 ok ->
                     get_id(Collection, Metric, Bucket, Key);
                 RAdd ->
                     RAdd
             end,
    case AddRes of
        {ok, MID} ->
            {Q, Vs} = update_tags(MID, Collection, NVs),
            T0 = erlang:system_time(),
            case pgapp:equery(Q, Vs) of
                {ok, _, _} ->
                    lager:debug("[dqe_idx:pg:update/5] Query too ~pms:"
                                " ~s <- ~p",
                                [dqe_idx_pg:tdelta(T0), Q, Vs]),
                    {ok, MID};
                E ->
                    lager:info("[dqe_idx:pg:update/5] Query failed after ~pms:"
                               " ~s <- ~p",
                               [dqe_idx_pg:tdelta(T0), Q, Vs]),
                    E
            end;
        EAdd ->
            EAdd
    end.

delete(Collection, Metric, Bucket, Key) ->
    Q = "DELETE FROM " ?MET_TABLE " WHERE collection = $1 AND " ++
        "metric = $2 AND bucket = $3 AND key = $4",
    Vs = [Collection, Metric, Bucket, Key],
    T0 = erlang:system_time(),
    case pgapp:equery(Q, Vs) of
        {ok, _} ->
            lager:debug("[dqe_idx:pg:delete/4] Query too ~pms: ~s <- ~p",
                        [tdelta(T0), Q, Vs]),
            ok;
        E ->
            lager:info("[dqe_idx:pg:delete/4] Query failed after ~pms: "
                       "~s <- ~p", [tdelta(T0), Q, Vs]),
            E
    end.

delete(Collection, Metric, Bucket, Key, Tags) ->
    case get_id(Collection, Metric, Bucket, Key) of
        not_found ->
            ok;
        {ok, ID} ->
            Rs = [delete(ID, Namespace, Name) || {Namespace, Name} <- Tags],
            case [R || R <- Rs, R /= ok] of
                [] ->
                    ok;
                [E | _] ->
                    E
            end;
        E ->
            E
    end.

delete(MetricID, Namespace, TagName) ->
    Q = "DELETE FROM " ?DIM_TABLE " WHERE metric_id = $1 AND "
        "namespace = $2 AND name = $3",
    Vs = [MetricID, Namespace, TagName],
    case pgapp:equery(Q, Vs) of
        {ok, _, _} ->
            ok;
        E ->
            E
    end.

%%====================================================================
%% Internal functions
%%====================================================================

tdelta(T0) ->
    (erlang:system_time() - T0)/1000/1000.

strip_tpl(L) ->
    [E || {E} <- L].

get_id(Collection, Metric, Bucket, Key) ->
    T0 = erlang:system_time(),
    Q = "SELECT id FROM " ?MET_TABLE " WHERE "
        "collection = $1 AND "
        "metric = $2 AND "
        "bucket = $3 AND "
        "key = $4",
    Vs = [Collection, Metric, Bucket, Key],
    case pgapp:equery(Q, Vs) of
        {ok, [_], [{ID}]} ->
            lager:debug("[dqe_idx:pg:get_id/4] Query too ~pms: ~s <- ~p",
                        [tdelta(T0), Q, Vs]),

            {ok, ID};
        {ok, _, _} ->
            not_found;
        E ->
            lager:info("[dqe_idx:pg:get_id/4] Query failed after ~pms:"
                       " ~s <- ~p", [tdelta(T0), Q, Vs]),
            E
    end.

add_tags(MID, Collection, Tags) ->
    Q = "INSERT INTO " ?DIM_TABLE " "
        "(metric_id, collection, namespace, name, value) VALUES ",
    OnConflict = "DO NOTHING",
    build_tags(MID, Collection, 1, OnConflict, Tags, Q, []).

update_tags(MID, Collection, Tags) ->
    Q = "INSERT INTO " ?DIM_TABLE " "
        "(metric_id, collection, namespace, name, value) VALUES ",
    OnConflict = "ON CONSTRAINT tags_metric_id_namespace_name_key "
        "DO UPDATE SET value = excluded.value",
    build_tags(MID, Collection, 1, OnConflict, Tags, Q, []).

build_tags(MID, Collection, P, OnConflict, [{NS, N, V}], Q, Vs) ->
    {[Q, tag_values(P), " ON CONFLICT ", OnConflict],
     lists:reverse([V, N, NS, Collection, MID | Vs])};

build_tags(MID, Collection, P, OnConflict, [{NS, N, V} | Tags], Q, Vs) ->
    Q1 = [Q, tag_values(P), ","],
    Vs1 = [V, N, NS, Collection, MID | Vs],
    build_tags(MID, Collection, P+5, OnConflict, Tags, Q1, Vs1).

tag_values(P)  ->
    [" ($", query_builder:i2l(P), ", "
     "$", query_builder:i2l(P + 1), ", "
     "$", query_builder:i2l(P + 2), ", "
     "$", query_builder:i2l(P + 3), ", "
     "$", query_builder:i2l(P + 4), ")"].
