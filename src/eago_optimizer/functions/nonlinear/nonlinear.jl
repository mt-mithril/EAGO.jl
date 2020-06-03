# Copyright (c) 2018: Matthew Wilhelm & Matthew Stuber.
# This work is licensed under the Creative Commons Attribution-NonCommercial-
# ShareAlike 4.0 International License. To view a copy of this license, visit
# http://creativecommons.org/licenses/by-nc-sa/4.0/ or send a letter to Creative
# Commons, PO Box 1866, Mountain View, CA 94042, USA.
#############################################################################
# EAGO
# A development environment for robust and global optimization
# See https://github.com/PSORLab/EAGO.jl
#############################################################################
# Defines the NonlinearExpression, BufferedNonlinearFunction
# unpack_value!
# Defines the Evaluator
# set_node_flag!
# set_node!
# set_reference_point!
# retrieve_node
# prior_eval
# copy_subexpression_value!
# forward_pass!
# reverse_pass!
# lower_interval_bound
# interval_bound
# eliminate_fixed_variables!
#############################################################################

include("empty_evaluator.jl")
include("univariate.jl")

"""
$(TYPEDEF)

Stores a general quadratic function with a buffer.
"""
mutable struct NonlinearExpression{V} <: AbstractEAGOConstraint

    "List of nodes in nonlinear expression"
    nd::Vector{JuMP.NodeData}
    "Adjacency Matrix for the expression"
    adj::SparseMatrixCSC{Bool,Int64}
    const_values::Vector{Float64}

    setstorage::Vector{V}
    numberstorage::Vector{Float64}
    isnumber::Vector{Bool}
    value::V
    value_available::Bool

    tp1storage::Vector{Float64}
    tp2storage::Vector{Float64}
    tp3storage::Vector{Float64}
    tp4storage::Vector{Float64}
    tpdict::Dict{Int64,Tuple{Int64,Int64,Int64,Int64}}

    # sparsity of constraint + indices in node to reference
    grad_sparsity::Vector{Int64}       # indices of variables in the problem space (size = np)

    # role in problem
    dependent_variable_count::Int
    dependent_subexpression_count::Int
    dependent_subexpressions::Vector{Int64}
    linearity::JuMP._Derivatives.Linearity
end

"""
$(TYPEDEF)

Stores a general nonlinear function with a buffer represented by the sum of a tape
and a scalar affine function.
"""
mutable struct BufferedNonlinearFunction{V} <: AbstractEAGOConstraint
    expr::NonlinearExpression{V}
    saf::SAF
    lower_bound::Float64
    upper_bound::Float64
    last_relax_convex::Bool
    last_relax_concave::Bool
    last_past_reverse::Bool
    has_value::Bool
end

###
### Constructor definitions
###
function NonlinearExpression(sub::JuMP._SubexpressionStorage,
                             subexpr_linearity::Vector{JuMP._Derivatives.Linearity},
                             tag::T) where T <: RelaxTag
    nd = copy(func.nd)
    adj = copy(func.adj)
    const_values = copy(func.const_values)

    lenx = length(nd)
    setstorage = fill(MC{N,T}(Interval(-Inf, Inf)), lenx)
    numberstorage = zeros(lenx)
    isnumber = fill(false, lenx)

    tpdict = Dict{Int64,Tuple{Int64,Int64,Int64,Int64}}()
    tp1_count = 0
    tp2_count = 0
    for i = 1:lenx
        node = @inbounds nd[i]
        op = node.index
        if double_tp(op)
            tp1_count += 1
            tpdict[i] = (tp1_count, tp1_count, tp2_count, tp2_count)
        elseif single_tp(op)
            tp1_count += 1
            tp2_count += 1
            tpdict[i] = (tp1_count, tp1_count, -1, -1)
        end
    end
    tp1storage = zeros(tp1_count)
    tp2storage = zeros(tp1_count)
    tp3storage = zeros(tp2_count)
    tp4storage = zeros(tp2_count)

    dependent_subexpressions = copy(func.dependent_subexpressions)
    dependent_subexpression_count = length(dependent_subexpressions)

    linearity = JuMP._Derivatives.classify_linearity(nd, adj, subexpr_linearity)

    # counts varialbes in subexpression
    variable_dict = Dict{Int,Bool}()
    for node in nd
        if node.nodetype === JuMP._Derivatives.VARIABLE
            indx = node.index
            if !haskey(variable_dict, indx)
                variable_dict[indx] = true
            end
        end
    end
    grad_sparsity = collect(keys(variable_dict))
    sort!(grad_sparsity)

    dependent_variable_count = length(grad_sparsity)
    N = dependent_variable_count

    subexpression = NonlinearExpression{MC{N,T}}(nd, adj, const_values, setstorage, numberstorage,
                                                 isnumber, zero(MC{N,T}), false,
                                                 tp1storage, tp2storage,
                                                 tp3storage, tp4storage, tpdict, grad_sparsity,
                                                 dependent_variable_count,
                                                 dependent_subexpression_count,
                                                 dependent_subexpressions,
                                                 JuMP._Derivatives.CONSTANT)
    return subexpression
end

function NonlinearExpression()
    return NonlinearExpression{MC{1,NS}}(JuMP.NodeData[], spzeros(Bool, 1), Float64[],
                                         MC{1,NS}[], Float64[], Bool[], zero(MC{1,NS}), false,
                                         Float64[], Float64[], Float64[], Float64[],
                                         Dict{Int64,Tuple{Int64,Int64,Int64,Int64}}(),
                                         Int64[], 0, 0, Int64[], JuMP._Derivatives.CONSTANT)
end

function BufferedNonlinearFunction(func::JuMP._FunctionStorage, bnds::MOI.NLPBoundsPair,
                                   subexpr_linearity::Vector{JuMP._Derivatives.Linearity},
                                   tag::T) where T <: RelaxTag

    nd = copy(func.nd)
    adj = copy(func.adj)
    const_values = copy(func.const_values)

    grad_sparsity = copy(func.grad_sparsity)  # sorted by JUmp, _FunctionStorage
    N = length(grad_sparsity)
    dependent_variable_count = length(grad_sparsity)

    lenx = length(nd)
    setstorage = fill(MC{N,T}(Interval(-Inf, Inf)), lenx)
    numberstorage = zeros(lenx)
    isnumber = fill(false, lenx)

    tpdict = Dict{Int64,Tuple{Int64,Int64,Int64,Int64}}()
    tp1_count = 0
    tp2_count = 0
    for i = 1:lenx
        node = @inbounds nd[i]
        op = node.index
        if double_tp(op)
            tp1_count += 1
            tpdict[i] = (tp1_count, tp1_count, tp2_count, tp2_count)
        elseif single_tp(op)
            tp1_count += 1
            tp2_count += 1
            tpdict[i] = (tp1_count, tp1_count, -1, -1)
        end
    end

    tp1storage = zeros(tp1_count)
    tp2storage = zeros(tp1_count)
    tp3storage = zeros(tp2_count)
    tp4storage = zeros(tp2_count)

    dependent_subexpressions = copy(func.dependent_subexpressions)
    dependent_subexpression_count = length(dependent_subexpressions)

    linearity = JuMP._Derivatives.classify_linearity(nd, adj, subexpr_linearity)

    expression = NonlinearExpression{MC{N,T}}(nd, adj, const_values, setstorage, numberstorage,
                                              isnumber, zero(MC{N,T}), false,
                                              tp1storage, tp2storage, tp3storage, tp4storage,
                                              tpdict, grad_sparsity, dependent_variable_count,
                                              dependent_subexpression_count,
                                              dependent_subexpressions,
                                              JuMP._Derivatives.CONSTANT)

    saf = SAF(SAT[SAT(0.0, VI(i)) for i = 1:length(grad_sparsity)], 0.0)

    lower_bound = bnds.lower
    upper_bound = bnds.upper

    last_relax_convex = false
    last_relax_concave = false
    last_past_reverse = false
    has_value = false


    return BufferedNonlinearFunction{MC{N,T}}(expression, saf, lower_bound, upper_bound,
                                              last_relax_convex, last_relax_concave,
                                              last_past_reverse, has_value)
end

function BufferedNonlinearFunction()
    return BufferedNonlinearFunction{MC{1,NS}}(NonlinearExpression(), SAF(SAT[], 0.0),
                                               -Inf, Inf, false, false, false, false)
end

function set_value!(expr::NonlinearExpression{V}, val::V) where V
    expr.value = val

    return nothing
end

function set_node_flag!(f::BufferedNonlinearFunction{V}) where V
    f.last_relax_convex = false
    f.last_relax_concave = false

    return nothing
end

"""
$(FUNCTIONNAME)

Extracts the `convex` affine relaxaiton is `use_cvx` to `f.saf` then adds the `affine_terms` to
this to form the affine relaxation of the function.
"""
function unpack_value!(f::BufferedNonlinearFunction{MC{N,T}}, x::Vector{Float64}, use_cvx::Bool) where {N,T<:RelaxTag}

    value = f.expr.value
    grad_sparsity = f.expr.grad_sparsity
    subgrad = use_cvx ? value.cv_grad : -value.cc_grad
    f.saf.constant = use_cvx ? value.cv : -value.cc
    for i = 1:N
        vval = @inbounds grad_sparsity[i]
        coef = @inbounds subgrad[i]
        f.saf.terms[i] = SAT(coef, VI(vval))
        f.saf.constant -= coef*(@inbounds x[vval])
    end

    return nothing
end

###
### Defines evaluator storage structure
###
"""
$(TYPEDEF)

MOI.AbstractNLPEvaluator for calculating relaxations of nonlinear terms.

Checks that the resulting value should be a number...

$(TYPEDFIELDS)
"""
Base.@kwdef mutable struct Evaluator <: MOI.AbstractNLPEvaluator

    user_operators::JuMP._Derivatives.UserOperatorRegistry = JuMP._Derivatives.UserOperatorRegistry()
    has_user_mv_operator::Bool = false
    num_mv_buffer::Vector{Float64} = Float64[]
    parameter_values::Vector{Float64} = Float64[]

    current_node::NodeBB = NodeBB()
    treat_x_as_number = Bool[]
    lower_variable_bounds::Vector{Float64} = Float64[]
    upper_variable_bounds::Vector{Float64} = Float64[]
    x::Vector{Float64} = Float64[]
    node_to_variable_map::Vector{Int64} = Int64[]
    variable_to_node_map::Vector{Int64} = Int64[]

    variable_count::Int = 0
    node_count::Int = 0

    cv_grad_buffer::Vector{Float64} = Float64[]
    cc_grad_buffer::Vector{Float64} = Float64[]

    "Context used to guard against domain violations & branch on these violations if necessary"
    subgrad_tighten::Bool = false
    subgrad_tighten_reverse::Bool = false
    ctx::GuardCtx = GuardCtx()

    subexpressions::Vector{NonlinearExpression} = NonlinearExpression[]
    subexpressions_eval::Vector{Bool} = Bool[]

    is_post::Bool = false
    is_intersect::Bool = false
    is_first_eval::Bool = false
end

"""
$(FUNCTIONNAME)

Sets the current node in the Evaluator structure.
"""
function set_node!(evaluator::Evaluator, n::NodeBB)

    evaluator.current_node = NodeBB(n)
    node_to_variable_map = evaluator.node_to_variable_map
    node_lower_bounds = n.lower_variable_bounds
    node_upper_bounds = n.upper_variable_bounds
    eval_lower_bounds = evaluator.lower_variable_bounds
    eval_upper_bounds = evaluator.upper_variable_bounds

    for i = 1:length(evaluator.current_node)
        full_variable_index = node_to_variable_map[i]
        eval_lower_bounds[full_variable_index] = node_lower_bounds[i]
        eval_upper_bounds[full_variable_index] = node_upper_bounds[i]
    end
    fill!(evaluator.subexpressions_eval, false)

    return nothing
end

function set_reference_point!(evaluator::Evaluator, x::Vector{Float64})
    fill!(evaluator.subexpressions_eval, false)

    return nothing
end

function retrieve_node(d::Evaluator)
    cn = d.current_node
    node_to_variable_map = d.node_to_variable_map
    return NodeBB(copy(d.lower_variable_bounds[node_to_variable_map]),
                  copy(d.upper_variable_bounds[node_to_variable_map]),
                  cn.lower_bound, cn.upper_bound, cn.depth, cn.id)
end

# Returns false if subexpression has been evaluated at current reference point
prior_eval(d::Evaluator, i::Int64) = @inbounds subexpressions_eval[i]

#=
Assumes the sparsities are sorted...
=#
function copy_subexpression_value!(k::Int, op::Int, subexpression::NonlinearExpression{MC{N1,T}},
                                   numvalued::Vector{Bool}, numberstorage::Vector{Float64}, setstorage::Vector{MC{N2,T}},
                                   cv_buffer::Vector{Float64}, cc_buffer::Vector{Float64},
                                   func_sparsity::Vector{Int64}) where {N1, N2, T <: RelaxTag}

    # fill cv_grad/cc_grad buffers
    sub_sparsity = subexpression.grad_sparsity
    sset = subexpression.setstorage[1]
    fill!(cv_buffer, 0.0)
    fill!(cc_buffer, 0.0)

    sub_sparsity_count = 1
    subs_index = @inbounds sub_sparsity[1]
    for i = 1:length(func_sparsity)
        func_index = @inbounds func_sparsity[i]
        if func_index === subs_index
            @inbounds cv_buffer[i] = sset.cv_grad[sub_sparsity_count]
            @inbounds cc_buffer[i] = sset.cc_grad[sub_sparsity_count]
            sub_sparsity_count += 1
            subs_index = @inbounds sub_sparsity[sub_sparsity_count]
        end
    end

    cv_grad = SVector(cv_buffer)
    cc_grad = SVector(cc_buffer)

    setstorage[k] = MC{N1,T}(sset.cv, sset.cc, sset.Intv, cv_grad, cc_grad, sset.cnst)

    return nothing
end

include("forward_pass.jl")

###
### Define forward evaluation pass
###
function forward_pass!(evaluator::Evaluator, d::NonlinearExpression{V}) where V
    # check that prior subexpressions have been evaluated
    # i.e. box_id is same and reference point is the same
    for i = 1:d.dependent_subexpression_count
        if !prior_eval(evaluator, i)
            subexpr = evaluator.subexpressions[i]
            forward_pass!(evaluator, subexpr)
        end
    end
    forward_pass_kernel!(d.nd, d.adj, evaluator.x, evaluator.lower_variable_bounds,
                         evaluator.upper_variable_bounds, d.setstorage,
                         d.numberstorage, d.isnumber, d.tpdict,
                         d.tp1storage, d.tp2storage, d.tp3storage, d.tp4storage,
                         evaluator.user_operators, evaluator.subexpressions,
                         d.grad_sparsity, evaluator.variable_to_node_map,
                         evaluator.num_mv_buffer, evaluator.ctx,
                         evaluator.is_post, evaluator.is_intersect,
                         evaluator.is_first_eval, evaluator.cv_grad_buffer,
                         evaluator.cc_grad_buffer, evaluator.treat_x_as_number)
    return nothing
end

function forward_pass!(evaluator::Evaluator, d::BufferedNonlinearFunction{V}) where V
    forward_pass!(evaluator, d.expr)
    set_value!(d.expr, d.expr.value ∩ Interval(d.lower_bound, d.upper_bound))
    d.has_value = true
    d.last_past_reverse = false

    return nothing
end

###
### Define backwards evaluation pass
###

include("reverse_pass.jl")

"""
$(FUNCTIONNAME)

A reverse_pass! on a `BufferedNonlinear` structure `d` intersects the existing value of the `d` with
constraint bounds then reverse propagates a set-valued operator (by default McCormick operator) along the
computational tape. The tapes are updated in place and boolean value is returned indicating whether the
reverse propagation yeilded a infeasible point (true = still feasible, false is proved infeasible).
"""
function reverse_pass!(evaluator::Evaluator, d::NonlinearExpression{V}) where V
    return reverse_pass_kernel!(d.nd, d.adj, evaluator.x, evaluator.lower_variable_bounds,
                                evaluator.upper_variable_bounds, d.setstorage,
                                d.numberstorage, d.isnumber, evaluator.is_post)
end

function reverse_pass!(evaluator::Evaluator, d::BufferedNonlinearFunction{V}) where V
    d.last_past_reverse = true
    set_value!(d.expr, d.expr.value ∩ Interval(d.lower_bound, d.upper_bound))

    return reverse_pass!(evaluator, d.expr)
end

###
### Interval bounding definitions
###
function lower_interval_bound(d::BufferedNonlinearFunction{V}, n::NodeBB) where V
    if !d.has_value
        forward_pass!(d.evaluator, d)
    end

    return get_lo(get_value(d))
end

function interval_bound(d::BufferedNonlinearFunction{V}, n::NodeBB) where V
    if !d.has_value
        forward_pass!(d.evaluator, d)
    end

    return get_interval(get_value(d))
end

###
### Parsing definitions
###
function eliminate_fixed_variables!(f::NonlinearExpression{V}, v::Vector{VariableInfo}) where V
    num_constants = length(f.const_values)
    indx_to_const_loc = Dict{Int,Int}()
    for i = 1:length(expr.nd)
        nd = @inbounds expr.nd[i]
        # Assumes MOI Variable have been eliminated previously...
        if nd.nodetype === JuMP._Derivatives.VARIABLE
            indx = nd.index
            if v[indx].is_fixed
                if haskey(indx_to_const_loc, indx)
                    const_loc = indx_to_const_loc[indx]
                    expr.nd[i] = NodeData(JuMP._Derivatives.VALUE, const_loc, nd.parent)
                else
                    push!(const_values, v[indx].lower_bound)
                    num_constants += 1
                    indx_to_const_loc[indx] = num_constants
                    expr.nd[i] = NodeData(nd.nodetype, num_constants, nd.parent)
                end
                f.isnumber[i] = true
            end
        end
    end

    return nothing
end

function eliminate_fixed_variables!(f::BufferedNonlinearFunction{V}, v::Vector{VariableInfo}) where V
    eliminate_fixed_variables!(f.expr, v)
end
