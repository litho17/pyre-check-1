(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Ast
open Statement
open Domains
open Interprocedural

module Flow : sig
  type t = {
    source_taint: ForwardTaint.t;
    sink_taint: BackwardTaint.t;
  }
  [@@deriving show]

  val bottom : t

  val is_bottom : t -> bool

  val join : t -> t -> t
end

(* A unique identifier that represents the first sink of an issue. *)
module SinkHandle : sig
  type t =
    | Call of {
        callee: Target.t;
        index: int;
        parameter: AccessPath.Root.t;
      }
    | Global of {
        callee: Target.t;
        index: int;
      }
    | Return
    | LiteralStringSink of Sinks.t
    | ConditionalTestSink of Sinks.t

  val make_call : call_target:CallGraph.CallTarget.t -> root:AccessPath.Root.t -> t

  val make_global : call_target:CallGraph.CallTarget.t -> t
end

module SinkTreeWithHandle : sig
  type t = {
    sink_tree: BackwardState.Tree.t;
    handle: SinkHandle.t;
  }

  val filter_bottom : t list -> t list

  (* Discard handles, join sink trees into a single tree. *)
  val join : t list -> BackwardState.Tree.t
end

module Handle : sig
  type t = {
    code: int;
    callable: Target.t;
    sink: SinkHandle.t;
  }
  [@@deriving compare]
end

module LocationSet : Stdlib.Set.S with type elt = Location.WithModule.t

type t = {
  flow: Flow.t;
  handle: Handle.t;
  locations: LocationSet.t;
  (* Only used to create the Pyre errors. *)
  define: Ast.Statement.Define.t Ast.Node.t;
}

type issue = t

val canonical_location : t -> Location.WithModule.t

val to_json
  :  taint_configuration:TaintConfiguration.Heap.t ->
  expand_overrides:OverrideGraph.SharedMemory.t option ->
  is_valid_callee:
    (port:AccessPath.Root.t -> path:Abstract.TreeDomain.Label.path -> callee:Target.t -> bool) ->
  filename_lookup:(Reference.t -> string option) ->
  t ->
  Yojson.Safe.t

val to_error : taint_configuration:TaintConfiguration.Heap.t -> t -> Error.t

(* A set of triggered sink kinds. *)
module TriggeredSinkHashSet : sig
  type t

  val create : unit -> t

  val is_empty : t -> bool

  val mem : t -> Sinks.partial_sink -> bool

  val add : t -> Sinks.partial_sink -> unit
end

(* A map from locations to a backward taint of triggered sinks.
 * This is used to store triggered sinks found in the forward analysis,
 * and propagate them up in the backward analysis. *)
module TriggeredSinkLocationMap : sig
  type t

  val create : unit -> t

  val add : t -> location:Location.t -> taint:BackwardState.t -> unit

  val get : t -> location:Location.t -> BackwardState.t
end

(* Accumulate flows and generate issues. *)
module Candidates : sig
  type t

  val create : unit -> t

  (* Check for issues in flows from the `source_tree` to the `sink_tree`, updating
   * issue `candidates`. *)
  val check_flow
    :  t ->
    location:Location.WithModule.t ->
    sink_handle:SinkHandle.t ->
    source_tree:ForwardState.Tree.t ->
    sink_tree:BackwardState.Tree.t ->
    unit

  (* Check for issues for combined source rules.
   * For flows where both sources are present, this adds the flow to issue `candidates`.
   * If only one source is present, this creates a triggered sink in `triggered_sinks_for_call`.
   *)
  val check_triggered_flows
    :  t ->
    taint_configuration:TaintConfiguration.Heap.t ->
    triggered_sinks_for_call:TriggeredSinkHashSet.t ->
    location:Location.WithModule.t ->
    sink_handle:SinkHandle.t ->
    source_tree:ForwardState.Tree.t ->
    sink_tree:BackwardState.Tree.t ->
    unit

  val generate_issues
    :  t ->
    taint_configuration:TaintConfiguration.Heap.t ->
    define:Define.t Node.t ->
    issue list
end
