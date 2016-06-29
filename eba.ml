
open Batteries
open Cmdliner

module L = LazyList

type checks = {
	  chk_uninit : bool
	; chk_dlock  : bool
	; chk_birq   : bool
}

let run_checks checks file fileAbs :unit =
	let run_check_fun fd in_func =
		 in_func fileAbs fd |> L.iter (function errmsg ->
			Printf.printf "\nPotential BUG found:\n%s\n\n" errmsg
		 )
	in
	let fds = Cil.(file.globals) |> List.filter_map (function
		| Cil.GFun(fd,_) -> Some fd
		| ______________ -> None
	)
	in
	(* THINK: Too much if-ery? *)
	fds |> List.iter (fun fd ->
		Log.debug "Analyzing function %s\n" Cil.(fd.svar.vname);
		if checks.chk_uninit
		then run_check_fun fd CheckUninitFlow1.in_func;
		if checks.chk_dlock
		then run_check_fun fd CheckDLockFlow2.in_func;
		if checks.chk_birq
		then run_check_fun fd CheckBhOnIrqFlow2.in_func;
	)

let infer_file checks fn =
	let file = Frontc.parse fn () in
	let fileAbs = Infer.of_file file in
	if Opts.Get.save_abs()
	then begin
		let fn_abs = fn ^ ".abs" in
		File.with_file_out fn_abs (fun out -> FileAbs.fprint out fileAbs)
	end;
	run_checks checks file fileAbs;
	if Opts.Get.gc_stats()
	then begin
		Printf.fprintf stderr "======= GC stats =======\n";
		Gc.print_stat stderr;
		Printf.fprintf stderr "========================\n"
	end


(* CLI *)

let log_level_of_int = function
	| x when x <= 0 -> Log.ERROR
	| 1 -> Log.WARN
	| 2 -> Log.INFO
	| x -> Log.DEBUG (* x >= 3 *)

let infer_files verbosity
		flag_gcstats flag_saveabs
		flag_no_inlining
		flag_no_dce flag_no_dfe
		flag_safe_casts flag_externs_do_nothing
		chk_uninit chk_dlock chk_birq
		files =
	(* CIL: do not print #line directives. *)
	Cil.lineDirectiveStyle := None;
	Log.color_on();
	Log.set_log_level (log_level_of_int verbosity);
	Opts.Set.gc_stats flag_gcstats;
	Opts.Set.save_abs flag_saveabs;
	Opts.Set.fp_inlining (not flag_no_inlining);
	Opts.Set.dce (not flag_no_dce);
	Opts.Set.dfe (not flag_no_dfe);
	Opts.Set.unsafe_casts (not flag_safe_casts);
	Opts.Set.externs_do_nothing flag_externs_do_nothing;
	let checks = { chk_uninit; chk_dlock; chk_birq } in
	List.iter (infer_file checks) files

let files = Arg.(non_empty & pos_all file [] & info [] ~docv:"FILE")

(* TODO: Write a Cmdliner.converter for Log.log_level *)
let verbose =
	let doc = "Set the verbosity level." in
	Arg.(value & opt int 0 & info ["v"; "verbose"] ~docv:"LEVEL" ~doc)

let flag_gcstats =
	let doc = "Print GC stats after analyzing a C file." in
	Arg.(value & flag & info ["gc-stats"] ~doc)

let flag_saveabs =
	let doc = "Save effect abstraction to an .abs file." in
	Arg.(value & flag & info ["save-abs"] ~doc)

let flag_no_inlining =
	let doc = "Do not inline function calls." in
	Arg.(value & flag & info ["no-inlining"] ~doc)

let flag_no_dce =
	let doc = "Do not eliminate dead code." in
	Arg.(value & flag & info ["no-dce"] ~doc)

let flag_no_dfe =
	let doc = "Do not ignore unused fields in structure types (aka dead field elimination)." in
	Arg.(value & flag & info ["no-dfe"] ~doc)

let flag_safe_casts =
	let doc = "Fail on potentially unsafe casts." in
	Arg.(value & flag & info ["safe-casts"] ~doc)

let flag_externs_do_nothing =
	let doc = "Ignore potential side-effects of extern functions." in
	Arg.(value & flag & info ["externs-do-nothing"] ~doc)

let check_uninit =
	let doc = "Check for uses of variables before initialization" in
	Arg.(value & flag & info ["U"; "uninit"] ~doc)

let check_dlock =
	let doc = "Check for double locking" in
	Arg.(value & flag & info ["L"; "dlock"] ~doc)

let check_birq =
	let doc = "Check for BH-enabling while IRQs are off" in
	Arg.(value & flag & info ["B"; "bh-irq"] ~doc)

let cmd =
	let doc = "Effect-based analysis of C programs" in
	let man = [ `S "DESCRIPTION"; `P "Author: Iago Abal <mail@iagoabal.eu>."; ] in
	Term.(pure infer_files
		$ verbose
		$ flag_gcstats $ flag_saveabs
		$ flag_no_inlining $ flag_no_dce $ flag_no_dfe
		$ flag_safe_casts $ flag_externs_do_nothing
		$ check_uninit $ check_dlock $ check_birq
		$ files),
	Term.info "eba" ~version:"0.1.0" ~doc ~man

let () = match Term.eval cmd with `Error _ -> exit 1 | _ -> exit 0
