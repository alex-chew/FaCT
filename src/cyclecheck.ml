open Util
open Pos
open Err
open Tast

module StringMap = Map.Make(String)
module StringSet = Set.Make(String)

class cyclechecker m =
  object (visit)
    inherit Tastmap.tast_visitor m as super
    val mutable _edges : fun_name list StringMap.t = StringMap.empty

    method _edges () = _edges

    method stm (stm_,lbl) =
      begin
        match stm_.data with
          | FnCall (fn,_,_,_)
          | VoidFnCall (fn,_) ->
            let fns = StringMap.find_opt
                        _cur_fn.data
                        _edges
                      >!> [] in
              _edges <- StringMap.add
                          _cur_fn.data
                          (fn :: fns)
                          _edges;
          | _ -> ()
      end;
      super#stm (stm_,lbl)

  end

let transform m =
  let visit = new cyclechecker m in
  let m' = visit#fact_module () in
  let Module(sdecs,fdecs,minfo) = m' in
  let edges = visit#_edges () in
  let sorted = ref [] in
  let perm_marked  = ref StringSet.empty in
  let rec visit p callstack =
    let caller = List.hd callstack in
      if not @@ StringSet.mem caller !perm_marked then
        begin
          if List.mem caller (List.tl callstack) then
            raise @@ cerr p
                       "recursion detected: %s"
                       (List.fold_left
                          (fun str fn -> fn ^ " -> " ^ str)
                          caller
                          (List.tl callstack));
          let callees = StringMap.find_opt caller edges >!> [] in
            List.iter
              (fun callee -> visit callee.pos (callee.data::callstack))
              callees;
            perm_marked := StringSet.add caller !perm_marked;
            sorted := caller :: !sorted
        end
  in
    StringMap.iter
      (fun caller _ -> visit fake_pos [caller])
      edges;
    let fdecs' =
      (* topological sort, callers first *)
      List.map
        (fun fn ->
           List.find
             (function
               | {data=FunDec(fn',_,_,_,_) | CExtern(fn',_,_)} when fn'.data = fn -> true
               | _ -> false)
             fdecs)
        !sorted in
    let standalones =
      List.filter
        (fun {data=FunDec(fn',_,_,_,_)|CExtern(fn',_,_)} ->
           not @@ List.mem fn'.data !sorted)
        fdecs in
      Module(sdecs,fdecs' @ standalones,minfo)
