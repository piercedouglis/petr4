open Core_kernel
module C = Csyntax
module P4 = Types

module Map = Map.Make(String)
module Env = struct
  type t = C.cexpr Map.t
end

(* Type of a compiler producing syntax in 'a. *)
type 'a comp = Env.t -> (Env.t * 'a) option

module CompOps = struct
  type 'a t = 'a comp

  let bind (c: 'a t) ~f:(f:'a -> 'b t) : 'b t = fun env ->
    match c env with
    | Some (env', a) -> f a env'
    | None -> None

  let return (a: 'a) =
    fun env -> Some (env, a)

  let map = `Define_using_bind

  let find_var (var: string) : (C.cexpr option) t =
    fun env -> Some (env, Map.find env var)

  let fail = fun env -> None
end

module CompM = Monad.Make(CompOps)

open CompM.Let_syntax
open Types.Expression 

let translate_expr (e: Prog.Expression.t) : C.cexpr comp =
  match (snd e).expr with
  | Name (BareName x) ->
    begin match%bind CompOps.find_var (snd x) with
      | Some e -> e |> return
      | None -> C.CVar (snd x) |> return
    end
  | _ -> (C.CIntLit 123) |> return

let translate_stmt (s: Prog.Statement.t) : C.cstmt comp =
  C.CVarInit (CInt, "todo", CIntLit 123) |> return

let rec translate_decl (d: Prog.Declaration.t) : C.cdecl comp =
  match snd d with
  | Struct {name; fields; _} ->
    let%bind cfields = translate_fields fields in
    C.CStruct (snd name, cfields) |> return
  | Header {name; fields; _} ->
    let%bind cfields = translate_fields fields in
    let valid = C.CField (CBool, "__header_valid") in
    C.CStruct (snd name, valid :: cfields) |> return
  | Parser { name; type_params; params; constructor_params; locals; states; _} -> 
    let%bind params = translate_params params in
    C.CStruct (snd name, params) |> return 
  | Function { return; name; type_params; params; body } -> failwith "Fds"
  | Control { annotations; name; type_params; params; constructor_params; locals; apply } ->
    let%bind params = translate_params params in
    C.CRec (C.CStruct (snd name, params), 
            C.CFun (CVoid, snd name ^ "_fun", 
                    [CParam (CTypeName (snd name), "*state")], 
                    apply_translate_emit apply)) |> return 
  | _ -> C.CInclude "todo" |> return
and translate_emit (s:Prog.Statement.t) : C.cdecl comp = 
  match (snd s).stmt with 
  | MethodCall { func; type_args; args } -> 
    C.CFun (CVoid, "func", [C.CParam (CVoid, "Fd")], [CRet (CVar "F")]) |> return 
  | _ ->  C.CFun (CVoid, "hold", [C.CParam (CVoid, "Fd")], [CRet (CVar "F")]) |> return 

and apply_translate_emit (apply : Prog.Block.t) = 
  let stmt = (snd apply).statements in 
  let rec m = List.map ~f:translate_emit stmt in 
  match m with
  | [] -> [C.CRet (CVar "")]
  | h::t -> C.CMethodCall h :: m t  

and translate_param (param : Typed.Parameter.t) : C.cfield comp =
  let%bind ctyp = translate_type param.typ in
  C.CField (ctyp, snd param.variable) |> return

and translate_params (params : Typed.Parameter.t list) : C.cfield list comp=
  params
  |> List.map ~f:translate_param
  |> CompM.all

and translate_field (field: Prog.Declaration.field) : C.cfield comp =
  let%bind ctyp = translate_type (snd field).typ in
  C.CField (ctyp, snd (snd field).name) |> return

and translate_fields (fields: Prog.Declaration.field list) =
  fields
  |> List.map ~f:translate_field
  |> CompM.all

and translate_type (typ: Typed.Type.t) : C.ctyp comp =
  match typ with
  | Typed.Type.Bool -> C.CBool |> return
  | Typed.Type.TypeName (BareName n) ->
    C.CTypeName (snd n) |> return
  | Typed.Type.Bit {width = 8} ->
    C.CBit8 |> return
  | _ -> C.CInt |> return

let translate_prog ((Program t): Prog.program) : C.cprog comp =
  t
  |> List.map ~f:translate_decl
  |> CompM.all

let compile (prog: Prog.program) : C.cprog =
  CInclude "petr4-runtime.h" ::
  match translate_prog prog Map.empty with
  | Some result -> snd result
  | None -> failwith "compilation failed (todo error message)"
