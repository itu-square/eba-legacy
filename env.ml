
open Batteries
open Type

(* THINK: We could keep global and local bindings separated, which may
   allow for some optimizations. For instance, we could incrementally
   compute (and zonk) global FVs, which is needed every time we infer
   the signature of a function definition.
 *)

module VarMap = Map.Make(
	struct
		type t = Cil.varinfo
		let compare x y = Cil.(compare x.vid y.vid)
	end)

type t = shape scheme VarMap.t

let empty = VarMap.empty

let cardinal = VarMap.cardinal

let find_opt = VarMap.Exceptionless.find

let find x (env :t) :shape scheme =
	match find_opt x env with
	| Some sch -> sch
	| None     ->
		Error.panic_with("Env.find: not found: " ^ Cil.(x.vname))

let add = VarMap.add

let remove = VarMap.remove

let (+::) : Cil.varinfo * shape scheme -> t -> t =
	fun (x,ty) -> add x ty

let (+>) (env1 :t) (env2 :t) :t =
	VarMap.fold VarMap.add env1 env2

let with_fresh x env :t * shape scheme =
	let z = Shape.ref_of Cil.(x.vtype) in
	let sch = Scheme.({ vars = QV.empty; body = z }) in
	(x,sch) +:: env, sch

let fresh_if_absent x env :t * shape scheme option =
	match find_opt x env with
	| None ->
		with_fresh x env |> Tuple.Tuple2.map2 Option.some
	| Some _ ->
		env, None

let of_bindings :(Cil.varinfo * shape scheme) list -> t =
	VarMap.of_enum % List.enum

let with_bindings bs env :t = of_bindings bs +> env

let zonk :t -> t =
	let open Scheme in
	let zonk_sch {vars; body} = {vars; body = Shape.zonk body}  in
	VarMap.map zonk_sch

let fv_of env :Vars.t =
	let open Scheme in
	VarMap.fold (fun _ {body = shp} ->
		Vars.union (Shape.fv_of shp)
	) env Vars.empty

let zonk_diet_fv_of env :DietFV.t =
	let open Scheme in
	VarMap.fold (fun _ sch ->
		DietFV.(union (of_scheme (Scheme.zonk sch)))
	) env DietFV.empty

let print_binding out (x,sch) =
	Printf.fprintf out "%s : %s\n" Cil.(x.vname) Scheme.(to_string sch)

let fprint out = List.iter (print_binding out) % VarMap.bindings

let print = fprint IO.stdout

let eprint = fprint IO.stderr
