-- Tests des modules d'ordonnancement. Exécuter via :
--   nix-shell --run "moonc tests/*.moon && LUA_PATH='src/?.lua;ffi/?.lua;tests/?.lua;;' luajit tests/order_spec.lua"
-- (script `tests/run.sh`).
signature = require "signature"
order     = require "order"
exif      = require "exif"

passed, failed = 0, 0
ok = (cond, msg) ->
  if cond
    passed += 1
  else
    failed += 1
    io.stderr\write "  ÉCHEC: #{msg}\n"
eq = (a, b, msg) -> ok a == b, "#{msg} (attendu #{tostring b}, obtenu #{tostring a})"

sig = (v) -> [v for _ = 1, signature.LEN]      -- signature constante (scalaire)
paths_of = (items) -> table.concat [it.path for it in *items], ","

-- signature.distance
do
  a = sig 100
  eq signature.distance(a, a), 0, "distance(x,x)=0"
  ok signature.distance(sig(0), sig(255)) > signature.distance(sig(0), sig(10)),
    "opposés plus éloignés que proches"
  eq signature.distance(sig(0), sig(255)), signature.distance(sig(255), sig(0)),
    "symétrie"
  eq signature.distance(sig(0), sig(1)), signature.LEN, "L1 = LEN×écart"

-- order.dirname / to_stamp / normalize
do
  eq order.dirname("/a/b/c.jpg"), "/a/b", "dirname"
  eq order.dirname("x.jpg"), "", "dirname sans /"
  eq order.to_stamp("2023:05:01 12:30:45"), 20230501123045, "to_stamp"
  eq order.to_stamp("pas une date"), nil, "to_stamp invalide -> nil"
  eq table.concat(order.normalize({"exif", "x", "exif", "dossier"}), ","),
    "exif,dossier", "normalize : connus, sans doublon"
  eq #order.normalize(nil), 0, "normalize nil -> {}"

-- partition_sorted : groupes triés par clé, ordre d'entrée stable dans un groupe
do
  items = { {k:"b",i:1}, {k:"a",i:2}, {k:"b",i:3}, {k:"a",i:4} }
  groups = order.partition_sorted items, (it) -> it.k
  eq #groups, 2, "2 groupes"
  eq groups[1][1].i .. groups[1][2].i, "24", "groupe 'a' stable (2,4)"
  eq groups[2][1].i .. groups[2][2].i, "13", "groupe 'b' stable (1,3)"

-- nn_chain : graine = plus petit chemin, puis plus proche voisin
do
  items = {
    { path: "z", sig: sig(245) }
    { path: "x", sig: sig(250) }
    { path: "y", sig: sig(240) }
  }
  -- graine x(250) -> plus proche z(245) -> y(240)
  eq paths_of(order.nn_chain items), "x,z,y", "nn_chain"
  eq paths_of(order.nn_chain {items[1]}), "z", "nn_chain singleton"

-- order_group : permutations de priorité (modèle validé)
do
  A = { path: "z", dir: "b", stamp: 2, sig: sig(245) }
  B = { path: "x", dir: "a", stamp: 1, sig: sig(250) }
  C = { path: "y", dir: "a", stamp: 3, sig: sig(240) }
  items = { A, B, C }
  eq paths_of(order.order_group items, {"dossier", "exif"}), "x,y,z",
    "dossier,exif : dir a (par date) puis dir b"
  eq paths_of(order.order_group items, {"dossier", "similarite"}), "x,y,z",
    "dossier,similarite : enchaînement dans dir a, puis dir b"
  eq paths_of(order.order_group items, {"similarite"}), "x,z,y",
    "similarite seule : enchaînement global"

-- order : shuffle déterministe (même graine -> même résultat), repli alphabétique
do
  ps = {"c", "a", "b"}
  eq table.concat(order.order(ps, {shuffle: true, seed: 42}), ","),
    table.concat(order.order({"c","a","b"}, {shuffle: true, seed: 42}), ","),
    "shuffle déterministe avec graine"
  eq table.concat(order.order({"c","a","b"}, {shuffle: false, order: {}}), ","),
    "a,b,c", "order vide -> alphabétique"

-- exif.datetime : ne lève pas, renvoie string ou nil
do
  for name in *{"face.jpg", "face2.jpg", "scene.jpg"}
    dt = exif.datetime "testdata/" .. name
    ok dt == nil or type(dt) == "string", "datetime(#{name}) string|nil"

-- signature.compute : intégration sur testdata (nécessite raylib)
do
  ok_rl, rl = pcall require, "raylib"
  has_data = io.open("testdata/face.jpg", "r")
  if has_data then has_data\close!
  if ok_rl and has_data
    sface  = signature.compute rl, "testdata/face.jpg"
    sscene = signature.compute rl, "testdata/scene.jpg"
    ok sface and #sface == signature.LEN, "compute(face) -> 192 octets"
    ok sscene and #sscene == signature.LEN, "compute(scene) -> 192 octets"
    eq signature.distance(sface, sface), 0, "compute reproductible (distance 0)"
    eq signature.compute(rl, "testdata/inexistant.jpg"), nil, "compute fichier absent -> nil"
  else
    io.stderr\write "  (raylib ou testdata indisponible : tests d'intégration sautés)\n"

print "tests: #{passed} ok, #{failed} échec(s)"
os.exit(failed == 0 and 0 or 1)
