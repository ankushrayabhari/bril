open! Core
open! Common

type t = {
  name : string;
  args : Dest.t list;
  ret_type : Bril_type.t option;
  blocks : Instr.t list String.Map.t;
  order : string list;
  cfg : string list String.Map.t;
}
[@@deriving compare, sexp_of]

let instrs { blocks; order; _ } = List.concat_map order ~f:(Map.find_exn blocks)

let process_instrs instrs =
  let block_name i = sprintf "block%d" i in
  let (name, block, blocks) =
    List.fold
      instrs
      ~init:(block_name 0, [], [])
      ~f:(fun (name, block, blocks) (instr : Instr.t) ->
        match instr with
        | Label label ->
          if List.is_empty block then (label, [], blocks)
          else (label, [], (name, List.rev block) :: blocks)
        | Jmp _
        | Br _
        | Ret _ ->
          let blocks = (name, List.rev (instr :: block)) :: blocks in
          (block_name (List.length blocks), [], blocks)
        | _ -> (name, instr :: block, blocks))
  in
  let blocks =
    (name, List.rev block) :: blocks
    |> List.rev_filter ~f:(fun (_, block) -> not (List.is_empty block))
  in
  let order = List.map blocks ~f:fst in
  let cfg =
    List.mapi blocks ~f:(fun i (name, block) ->
        let next =
          match List.last_exn block with
          | Jmp label -> [ label ]
          | Br (_, l1, l2) -> [ l1; l2 ]
          | Ret _ -> []
          | _ ->
            ( match List.nth blocks (i + 1) with
            | None -> []
            | Some (label, _) -> [ label ] )
        in
        (name, next))
  in
  (String.Map.of_alist_exn blocks, order, String.Map.of_alist_exn cfg)

let of_json json =
  let open Yojson.Basic.Util in
  let arg_of_json json =
    (json |> member "name" |> to_string, json |> member "type" |> Bril_type.of_json)
  in
  let name = json |> member "name" |> to_string in
  let args = json |> member "args" |> to_list_nonnull |> List.map ~f:arg_of_json in
  let ret_type = json |> member "type" |> Bril_type.of_json_opt in
  let instrs = json |> member "instrs" |> to_list_nonnull |> List.map ~f:Instr.of_json in
  let (blocks, order, cfg) = process_instrs instrs in
  { name; args; ret_type; blocks; order; cfg }

let to_json t =
  `Assoc
    ( [
        ("name", `String t.name);
        ( "args",
          `List
            (List.map t.args ~f:(fun (name, bril_type) ->
                 `Assoc [ ("name", `String name); ("type", Bril_type.to_json bril_type) ])) );
        ("instrs", `List (instrs t |> List.map ~f:Instr.to_json));
      ]
    @ Option.value_map t.ret_type ~default:[] ~f:(fun t -> [ ("type", Bril_type.to_json t) ]) )
