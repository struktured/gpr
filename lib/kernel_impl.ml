open Lacaml.Impl.D
open Lacaml.Io

open Utils

module type From_all_vec = sig
  module Kernel : sig
    type t

    val get_sigma2 : t -> float
  end

  val eval_one : Kernel.t -> vec -> float
  val eval : Kernel.t -> vec -> vec -> float
  val eval_vec_col : Kernel.t -> vec -> mat -> int -> float
  val eval_mat_cols : Kernel.t -> mat -> int -> mat -> int -> float
  val eval_mat_col : Kernel.t -> mat -> int -> float
end

module Make_from_all_vec (Spec : From_all_vec) = struct
  module Kernel = Spec.Kernel

  let eval_mat_col = Spec.eval_mat_col
  let eval_mat_cols = Spec.eval_mat_cols
  let eval_one = Spec.eval_one
  let eval_vec_col = Spec.eval_vec_col

  module Inducing = struct
    type t = mat

    let size points = Mat.dim2 points

    let upper kernel mat =
      let n = Mat.dim2 mat in
      let dst = Mat.create n n in
      for i = 1 to n do
        dst.{i, i} <- eval_mat_col kernel mat i;
        for j = i + 1 to n do
          dst.{i, j} <- eval_mat_cols kernel mat i mat j;
        done
      done;
      dst
  end

  module Input = struct
    type t = vec

    let eval_one = eval_one

    let eval kernel ~inducing ~input =
      let n = Mat.dim2 inducing in
      let dst = Vec.create n in
      for col = 1 to n do
        dst.{col} <- eval_vec_col kernel input inducing col
      done;
      dst

    let weighted_eval kernel ~coeffs ~inducing ~input =
      let n = Vec.dim input in
      let res = ref 0. in
      for col = 1 to n do
        res := !res +. coeffs.{col} *. eval_vec_col kernel input inducing col
      done;
      !res
  end

  module Inputs = struct
    include Inducing

    let weighted_eval kernel ~coeffs ~inducing ~inputs =
      let n_inducing_inputs = Mat.dim2 inducing in
      let n_inputs = Mat.dim2 inputs in
      let dst = Vec.create n_inputs in
      for i = 1 to n_inputs do
        dst.{i} <- coeffs.{1} *. eval_mat_cols kernel inducing 1 inputs i;
        for j = 2 to n_inducing_inputs do
          dst.{i} <-
            dst.{i} +. coeffs.{j} *. eval_mat_cols kernel inputs i inducing j
        done
      done;
      dst

    let upper_no_diag kernel mat =
      let n = Mat.dim2 mat in
      let dst = Mat.create n n in
      for i = 1 to n do
        for j = i + 1 to n do
          dst.{i, j} <- eval_mat_cols kernel mat i mat j;
        done
      done;
      dst

    let cross kernel ~inducing ~inputs =
      let n1 = Mat.dim2 inducing in
      let n2 = Mat.dim2 inputs in
      let dst = Mat.create n1 n2 in
      for i = 1 to n1 do
        for j = 1 to n2 do
          dst.{i, j} <- eval_mat_cols kernel inducing i inputs j
        done
      done;
      dst

    let diag kernel mat =
      let n = Mat.dim2 mat in
      let dst = Vec.create n in
      for i = 1 to n do
        dst.{i} <- eval_mat_col kernel mat i
      done;
      dst
  end

(* TODO: this is surprisingly faster; maybe implement weighted, etc.,
   dot product operations on matrix columns, etc. in C.

  let evals vec1 mat ~dst =
    let n = Mat.dim2 mat in
    for i = 1 to n do
      let vec2 = Mat.col mat i in
      dst.{i} <- eval vec1 vec2
    done

  let weighted_eval ~coeffs vec1 mat =
    let n = Mat.dim2 mat in
    let res = ref 0. in
    for i = 1 to n do
      let vec2 = Mat.col mat i in
      res := !res +. coeffs.{i} *. eval vec1 vec2
    done;
    !res

  let weighted_evals ~coeffs mat1 mat2 ~dst =
    let n1 = Mat.dim2 mat1 in
    let n2 = Mat.dim2 mat2 in
    for i = 1 to n1 do
      let vec1 = Mat.col mat1 i in
      dst.{i} <- 0.;
      for j = 1 to n2 do
        let vec2 = Mat.col mat2 j in
        dst.{i} <- dst.{i} +. coeffs.{i} *. eval vec1 vec2
      done
    done

  let upper mat ~dst =
    let n = Mat.dim2 mat in
    for i = 1 to n do
      let vec1 = Mat.col mat i in
      for j = i to n do
        let vec2 = Mat.col mat j in
        dst.{j, i} <- eval vec1 vec2
      done
    done

  let cross mat1 mat2 ~dst =
    let n1 = Mat.dim2 mat1 in
    let n2 = Mat.dim2 mat2 in
    for i = 1 to n1 do
      let vec1 = Mat.col mat1 i in
      for j = 1 to n2 do
        let vec2 = Mat.col mat2 j in
        dst.{i, j} <- eval vec1 vec2
      done
    done

  let diag mat ~dst =
    let n = Mat.dim2 mat in
    for i = 1 to n do
      let vec = Mat.col mat i in
      dst.{i} <- eval vec vec
    done
*)
end

module Gauss_all_vec_spec = struct
  module Kernel = struct
    type t = {
      a : float;
      b : float;
      sigma2 : float;
    }

    let get_sigma2 k = k.sigma2
  end

  open Kernel

  let eval_rbf2 k r = exp (k.a +. k.b *. r)

  let eval_one k vec = eval_rbf2 k (Vec.ssqr vec)

  let eval k vec1 vec2 = eval_rbf2 k (Vec.ssqr_diff vec1 vec2)

  let eval_mat_col = fun k _mat _col -> exp k.a

  let eval_vec_col k vec mat col =
    let d = Vec.dim vec in
    let r2 = ref 0. in
    for i = 1 to d do
      let diff = vec.{i} -. mat.{i, col} in
      r2 := !r2 +. diff *. diff
    done;
    eval_rbf2 k !r2

  let eval_mat_cols k mat1 col1 mat2 col2 =
    let d = Mat.dim1 mat1 in
    let r2 = ref 0. in
    for i = 1 to d do
      let diff = mat1.{i, col1} -. mat2.{i, col2} in
      r2 := !r2 +. diff *. diff
    done;
    eval_rbf2 k !r2
end

module Gauss_all_vec = struct
  module X = Make_from_all_vec (Gauss_all_vec_spec)

  module Kernel = X.Kernel
  module Inducing = X.Inducing
  module Input = X.Input

  module Inputs = struct
    include X.Inputs

    open Gauss_all_vec_spec.Kernel

    let diag kernel mat = Vec.make (Mat.dim2 mat) (exp kernel.a)
  end
end

module Gauss_deriv_all_vec = struct
  module Eval_spec = Gauss_all_vec

  open Gauss_all_vec_spec.Kernel

  module Deriv_spec = struct
    module Kernel = Eval_spec.Kernel

    module Hyper = struct
      type t = A | B
    end

    module Inducing = struct
      type t = Eval_spec.Inducing.t
      type shared = Kernel.t * t

      let calc_shared k inducing =
        let cov = Eval_spec.Inducing.upper k inducing in
        cov, (k, cov)

      let calc_deriv (k, cov) = function
        | Hyper.A -> cov, None
        | Hyper.B ->
            let m = Mat.dim1 cov in
            let n = Mat.dim2 cov in
            let res = Mat.create m n in
            for c = 1 to n do
              for r = 1 to c do
                res.{r, c} <-
                  cov.{r, c} *. (log cov.{r, c} -. k.a) /. k.b
              done;
            done;
            res, None
    end

    module Inputs = struct
      type t = Eval_spec.Inputs.t
      type diag = Kernel.t * vec
      type cross = Kernel.t * t

      let calc_shared_diag k inputs =
        let vars = Eval_spec.Inputs.diag k inputs in
        vars, (k, vars)

      let calc_shared_cross k ~inducing ~inputs =
        let cross = Eval_spec.Inputs.cross k ~inducing ~inputs in
        cross, (k, cross)

      let deriv_b_mat k cov =
        let m = Mat.dim1 cov in
        let n = Mat.dim2 cov in
        let res = Mat.create m n in
        for c = 1 to n do
          for r = 1 to m do
            res.{r, c} <-
              cov.{r, c} *. (log cov.{r, c} -. k.a) /. k.b
          done;
        done;
        res

      let calc_deriv_diag (k, vars) = function
        | Hyper.A -> Some vars
        | Hyper.B ->
            Some (Mat.col (deriv_b_mat k (Mat.of_col_vecs [| vars |])) 1)

      let calc_deriv_cross (k, cross) = function
        | Hyper.A -> cross, None
        | Hyper.B -> deriv_b_mat k cross, None
    end
  end
end

module Wiener_all_vec_spec = struct
  module Kernel = struct
    type t = {
      a : float;
      sigma2 : float;
    }

    let get_sigma2 k = k.sigma2
  end

  open Kernel

  let eval_one k vec = exp k.a *. sqrt (Vec.ssqr vec)

  let eval k vec1 vec2 = exp k.a *. sqrt (min (Vec.ssqr vec1) (Vec.ssqr vec2))

  let eval_mat_col k mat col = eval_one k (Mat.col mat col)

  let eval_vec_col k vec mat col = eval k vec (Mat.col mat col)

  let eval_mat_cols k mat1 col1 mat2 col2 =
    eval k (Mat.col mat1 col1) (Mat.col mat2 col2)
end

module Wiener_all_vec = Make_from_all_vec (Wiener_all_vec_spec)