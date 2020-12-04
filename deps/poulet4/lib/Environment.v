Require Import Coq.Lists.List.
Require Import Coq.FSets.FMapList.
Require Import Coq.Structures.OrderedTypeEx.

Require Import Monads.Monad.
Require Import Monads.Option.
Require Import Monads.State.

Require Import CamlString.
Require Import Syntax.

Open Scope monad.

Module Import MStr := FMapList.Make(CamlStringOT).

Inductive exception :=
| PacketTooShort
| Reject
| Exit
| Internal
| AssertError (error_msg: caml_string).

Section Environment.

  Context (tags_t: Type).
  Context (tags_dummy: tags_t).

  Definition scope := MStr.t (Value tags_t).
  Definition environment := list scope.

  Definition env_monad := @state_monad environment exception.

  Definition map_env (f : environment -> environment) : env_monad unit :=
    fun env => mret tt (f env).

  Definition lift_env_fn (f : environment -> option environment) : env_monad unit :=
    fun env =>
      match f env with
      | Some env' => mret tt env'
      | None => state_fail Internal env
      end.

  Definition lift_env_lookup_fn (f: environment -> option (Value tags_t)) : env_monad (Value tags_t) :=
    fun env =>
      match f env with
      | Some res => mret res env
      | None => state_fail Internal env
      end.

  Definition lift_option {A : Type} (x: option A) : env_monad A := fun env => 
                                                                     match x with
                                                                     | Some it => mret it env
                                                                     | None => (inr Internal, env)
                                                                     end.

  Definition update_scope (key: caml_string) (val: (Value tags_t)) (bindings: scope) : option scope :=
    MStr.find key bindings;;
    mret (MStr.add key val (MStr.remove key bindings)).

  Definition insert_scope (key: caml_string) (val: (Value tags_t)) (bindings: scope) : option scope :=
    MStr.find key bindings;;
    mret (MStr.add key val bindings).

  Definition find_scope (key: caml_string) (bindings: scope) : option (Value tags_t) :=
    MStr.find key bindings.

  Definition push_scope (env: environment) :=
    MStr.empty _ :: env.

  Definition pop_scope (env: environment) : option environment :=
    match env with
    | _ :: rest => Some rest
    | nil => None
    end.

  Fixpoint update_environment' (key: caml_string) (val: (Value tags_t)) (env: environment) : option environment :=
    match env with
    | inner :: rest =>
      if MStr.find key inner
      then let* inner' := update_scope key val inner in
           mret (inner' :: rest)
      else let* rest' := update_environment' key val rest in
           mret (inner :: rest')
    | nil => None
    end.

  Definition update_environment (key: caml_string) (val: (Value tags_t)) : env_monad unit :=
    lift_env_fn (update_environment' key val).

  Definition insert_environment' (key: caml_string) (val: (Value tags_t)) (env: environment) : option environment :=
    match env with
    | inner :: rest =>
      let* inner' := insert_scope key val inner in
      mret (inner' :: rest)
    | nil => None
    end.

  Definition insert_environment (key: caml_string) (val: (Value tags_t)) : env_monad unit :=
    lift_env_fn (insert_environment' key val).

  Fixpoint find_environment' (key: caml_string) (env: environment) : option (Value tags_t) :=
    match env with
    | inner :: rest =>
      match MStr.find key inner with
      | Some v => Some v
      | None => find_environment' key rest
      end
    | nil => None
    end.

  Definition find_environment (key: caml_string) : env_monad (Value tags_t) :=
    lift_env_lookup_fn (find_environment' key).

  (* TODO handle name resolution properly *)
  Definition str_of_name_warning_not_safe (t: Typed.name) : caml_string :=
    match t with 
    | Typed.BareName s => s
    | Typed.QualifiedName _ s => s
    end.

  Fixpoint find_lvalue' (lval: ValueLvalue tags_t) (env: environment) : option (Value tags_t) :=
    let '(MkValueLvalue _ _ pre_lval _) := lval in
    match pre_lval with
    | ValLeftName _ _ var =>
      let s := str_of_name_warning_not_safe var in
      find_environment' s env
    | ValLeftMember _ _ lval' member =>
      let* val := find_lvalue' lval' env in
      match val with
      | ValBase _ (ValBaseRecord _ map) =>
        match (Raw.find member map) with
        | Some v => Some (ValBase _ v)
        | None => None
        end
      | _ => None
      end
    | _ => None (* TODO *)
    end.

  Definition find_lvalue (lval: ValueLvalue tags_t) : env_monad (Value tags_t) :=
    lift_env_lookup_fn (find_lvalue' lval).

  Definition update_member (obj: (Value tags_t)) (member: caml_string) (val: (Value tags_t)) : option (Value tags_t).
  Admitted.

  Fixpoint update_lvalue' (lval: ValueLvalue tags_t) (val: (Value tags_t)) (env: environment) : option environment :=
    let '(MkValueLvalue _ _ pre_lval _) := lval in
    match pre_lval with
    | ValLeftName _ _ var =>
      let s := str_of_name_warning_not_safe var in
      update_environment' s val env
    | ValLeftMember _ _ lval' member =>
      let* obj := find_lvalue' lval' env in
      let* obj' := update_member obj member val in
      update_lvalue' lval' obj' env
    | _ => None (* TODO *)
    end.

  Definition update_lvalue (lval: ValueLvalue tags_t) (val: (Value tags_t)) : env_monad unit :=
    lift_env_fn (update_lvalue' lval val).

  Definition toss_value (original: env_monad (Value tags_t)) : env_monad unit :=
    fun env =>
      match original env with
      | (inl result, env') => mret tt env'
      | (inr exc, env') => state_fail exc env'
      end.

  Definition dummy_value (original: env_monad unit) : env_monad (Value tags_t) :=
    fun env =>
      match original env with
      | (inl tt, env') => mret (ValBase _ (ValBaseNull _)) env'
      | (inr exc, env') => state_fail exc env'
      end.

End Environment.