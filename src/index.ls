q = -> """
    '#{ "#it".replace /'/g "''" }'
"""

qq = ->
    it.replace /\.(\d+)/g -> "[#{ parseInt(RegExp.$1) + 1}]"
      .replace /^(\w+)/ -> "#{ RegExp.$1.replace /"/g '""' }"

walk = (model, meta) ->
    return [] unless meta?[model]
    for col, spec of meta[model]
        [compile(model, spec), col]

compile = (model, field) ->
    {$query, $from, $and, $} = field ? {}
    switch
    | $from? => let from-table = qq "#{$from}s", model-table = qq "#{model}s" => """
        (SELECT COALESCE(ARRAY_TO_JSON(ARRAY_AGG(_)), '[]') FROM (SELECT * FROM #from-table
            WHERE #{ qq "_#model" } = #model-table."_id" AND #{
                switch
                | $query?                   => cond model, $query
                | _                         => true
            }
        ) AS _)
    """
    | $? => cond model, $
    | typeof field is \object => cond model, field
    | _ => field

cond = (model, spec) -> switch typeof spec
    | \number => spec
    | \string => qq spec
    | \object =>
        # Implicit AND on all k,v
        ([ test model, qq(k), v for k, v of spec ].reduce (++)) * " AND "
    | _ => it

test = (model, key, expr) -> switch typeof expr
    | <[ number boolean ]> => ["(#key = #expr)"]
    | \string => ["(#key = #{ q expr })"]
    | \object =>
        for op, ref of expr
            switch op
            | \$lt =>
                res = evaluate model, ref
                "(#key < #res)"
            | \$gt =>
                res = evaluate model, ref
                "(#key > #res)"
            | \$ => let model-table = qq "#{model}s"
                "#key = #model-table.#{ qq ref }"
            | _ => throw "Unknown operator: #op"
    | \undefined => [true]

evaluate = (model, ref) -> switch typeof ref
    | <[ number boolean ]> => "#ref"
    | \string => q ref
    | \object => for op, v of ref => switch op
        | \$ => let model-table = qq "#{model}s" => "#model-table.#{ qq v }" 
        | \$ago => "'now'::timestamptz - #{ q "#v ms" }::interval"
        | _ => continue

order-by = (fields) ->
    sort = for k, v of fields
        "#{qq k} " + switch v
        |  1 => \ASC
        | -1 => \DESC
        | _  => throw "unknown order type: #q #k"
    sort * ", "

export function pgrest_select({collection, l = 30, sk = 0, q, c, s, fo})
    cond = compile collection, q if q
    query = "SELECT * from #collection"

    query += " WHERE #cond" if cond?
    [{count}] = plv8.execute "select count(*) from (#query) cnt"
    return { count } if c

    query += " ORDER BY " + order-by s if s
    do
        paging: { count, l, sk }
        entries: plv8.execute "#query limit $1 offset $2" [l, sk]
        query: cond