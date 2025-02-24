(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type t =
  | Mutable
  | ReadOnly
[@@deriving compare, sexp, hash]

let pp format readonlyness =
  let string =
    match readonlyness with
    | Mutable -> "Mutable"
    | ReadOnly -> "ReadOnly"
  in
  Format.fprintf format "%s" string


let show = Format.asprintf "%a" pp

let name = "ReadOnlyness"

let bottom = Mutable

let less_or_equal ~left ~right =
  match left, right with
  | _, ReadOnly -> true
  | _ -> [%compare.equal: t] left right


let join left right =
  match left, right with
  | ReadOnly, _
  | _, ReadOnly ->
      ReadOnly
  | _ -> Mutable


let meet left right =
  match left, right with
  | Mutable, _
  | _, Mutable ->
      Mutable
  | _ -> ReadOnly


let of_type = function
  (* TODO(T130377746): Handle readonlyness for non-primitive types, such as `List`. *)
  | Type.ReadOnly _ -> ReadOnly
  | _ -> Mutable
