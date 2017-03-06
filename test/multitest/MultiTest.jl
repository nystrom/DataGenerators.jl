# Simplified equivalents of @mcheck macros from AutoTest.jl (Robert Feldt), implemented using customization features of Base.Test in Julia 0.5
# Adds new @mtest_distributed_as to test distributions
# Simon Poulding, 2017
#
#
# Examples:
#
# @mtestset "example of autorepeating (defaults to 30 repetitions)" begin
# 	@mtest_values_vary rand(1:6)
# end
#
# @mtestset "example of autorepeating - set explicitly" reps=7 begin
# 	@mtest_values_vary rand(1:6)
# end
#
# @mtestset "can use for syntax in same way as for @testset, and similarly creates a new test set for each value of loop var" for i in 1:10
# 	@mtest_values_vary rand(1:i)
# end
#
# using Distributions
# @mtestset "compares to a distribution (any type that rand(...) accepts) using MannWhitneyU with defined significance" begin
#	x = rand(1:6)
# 	@mtest_distributed_as x DiscreteUniform(1,6) 0.01
# 	@mtest_distributed_as x 1:6 0.01
# end
#
# @testset MultiTestSet "omit automatic looping" begin
# 	for x in ["i","j","k"]
# 		@mtest_values_include x ["k","i"]
# 	end
# end
#
# 
module MultiTest

export MultiTestSet
export @mtestset
export @mtest_values_vary, @mtest_values_are, @mtest_values_include, @mtest_that_sometimes, @mtest_distributed_as

import Base.Test: record, finish
using Base.Test: AbstractTestSet, DefaultTestSet, Result, Pass, Fail, Error, ExecutionResult, Returned, Threw, get_testset
using HypothesisTests

# wrap DefaultTestSet with additional fields for samples taken at mtest macros
# we need DefaulTestSet since it handles pretty printing and accummulation of results
type MultiTestSet <: AbstractTestSet
	defaultts::DefaultTestSet
	mtests::Dict{Symbol, Function}
	samples::Dict{Symbol, Vector}
	repetition_count::Int
	repetitions::Int
	function MultiTestSet(desc; reps::Int=30)
		new(DefaultTestSet(desc), Dict{Symbol, Function}(), Dict{Symbol, Vector}(), 0, reps)
	end
end 

# for normal tests, record against the wrapped default test set
record(ts::MultiTestSet, child::AbstractTestSet) = record(ts.defaultts, child)
record(ts::MultiTestSet, res::Result) = record(ts.defaultts, res)

# at end of multitest set, evaluate samples against corresponding mtest closures and record results in the wrapped default test set,
# then finish the wrapped test set so that results accumulate appropriately
function finish(ts::MultiTestSet)
	for (id, mtestclosure) in ts.mtests
		s = get(ts.samples, id, [])
		res = try
				result, macrosym, evaluand, params = mtestclosure(s)
				testdesc = string(macrosym) * " " * evaluand * " " * params * "\n      Sample: " * string(s) 	
				# this description (macrosym evaluand & any parameters) will be reported by DefaultTestSet after the label "Expression:"
				# the spaces after the \n aligns the label "Sample:" on the second line to this
				result ? Pass(macrosym, testdesc, nothing, nothing) : Fail(macrosym, testdesc, nothing, nothing)
			catch _e
				Error(:mtest, nothing, _e, catch_backtrace())
			end
		record(ts.defaultts, res)
	end
	finish(ts.defaultts)
end


# determine whether to continue with more repetitions
# this could be extend with accumulator-type functionality from AutoTest so that number of repeats (sample size) is adjusted automatically
function continue_sampling()
	ts = get_testset()
	ts.repetition_count += 1
	ts.repetition_count <= ts.repetitions
end

# syntatic sugar for @testset MultiTestSet, also insert a while loop around test set block that is controlled automatically
macro mtestset(args...)
	testsetex = args[end]
	@assert isa(testsetex, Expr) && (testsetex.head in (:block, :for))
	testsetblock = testsetex.head == :block ? testsetex : testsetex.args[2]
	@assert isa(testsetblock, Expr) && (testsetblock.head == :block)
	mtestloopex = quote
		while MultiTest.continue_sampling()
			$(testsetblock)
		end
	end
	if testsetex.head == :block
		testsetex = mtestloopex
	else
		testsetex.args[2] = mtestloopex
	end
	newargs = (:MultiTestSet, args[1:end-1]..., testsetex)
	mc = :( @testset($(newargs...)) )
	esc(mc)
end


# register a mtest macro first time it is executed, to record both id and the test function (as a closure including any parameters 
# such as expected results)
register_mtest(ts::MultiTestSet, id::Symbol, mtestclosure::Function) = ts.mtests[id] = mtestclosure

is_mtest_registered(ts::MultiTestSet, id::Symbol) = haskey(ts.mtests, id)

# add result to sample (or report error during test)
function add_to_mtest_sample(ts::MultiTestSet, id::Symbol, result::ExecutionResult, origex)
    if isa(result, Returned)
		s = get!(Vector{Any}, ts.samples, id)
		push!(s, result.value)
    else
        # The predicate couldn't be evaluated without throwing an
        # exception, so that is an Error and not a Fail
        @assert isa(result, Threw)
        testres = Error(:test_error, origex, result.exception, result.backtrace)
	    record(ts, testres)
    end
end


# simplified form of Base.Test.get_test_result: special handling for comparisons is removed as we don't need it (but see mtest_that_sometimes)
function get_mtest_result_expr(ex) 
    testret = :(Returned($(esc(ex)), nothing))
    resultex = quote
        try
            $testret
        catch _e
            Threw(_e, catch_backtrace())
        end
    end
    Base.remove_linenums!(resultex)
    resultex
end

# common code for all mtest macros: output is code to register mtest instance and its associated closure (if first time executed),
# and then add value to the sample
function mtest_macro(ex, paramex, mtestclosureex, macrosym)
    origex = Expr(:inert, ex)
    resultex = get_mtest_result_expr(ex)
	id = gensym(:mtest)
	idstr = string(id)
	tsvar = gensym(:ts)
    quote 
		$tsvar = get_testset()
		isa($tsvar, MultiTestSet) || error("To apply the @" * $(string(macrosym)) * " macro, replace @testset with @mtestset")
		if !is_mtest_registered($tsvar, Symbol($idstr))
			$paramex
			register_mtest($tsvar, Symbol($idstr), $mtestclosureex)
		end
		add_to_mtest_sample($tsvar, Symbol($idstr), $resultex, $origex)
	end
end

# mtest_values_vary
macro mtest_values_vary(ex)
	macrosym = :mtest_values_vary
	paramex = :( nothing ) 
	mtestclosureex = :( _s->(length(unique(_s))>1, Symbol($(string(macrosym))), $(string(ex)), "") )
	mtest_macro(ex, paramex, mtestclosureex, macrosym)
end

# mtest_values_are
macro mtest_values_are(ex, expex)
	macrosym = :mtest_values_are
	expvar = gensym(:exp)
	paramex = :( $expvar = $(esc(expex)) )
	mtestclosureex = :( _s->(sort(unique(_s))==sort(unique($expvar)), Symbol($(string(macrosym))), $(string(ex)), string($expvar)) )
	mtest_macro(ex, paramex, mtestclosureex, macrosym)
end

# mtest_values_include
macro mtest_values_include(ex, expex)
	macrosym = :mtest_values_include
	expvar = gensym(:exp)
	paramex = :( $expvar = $(esc(expex)) )
	mtestclosureex = :( _s->(issubset($expvar, _s), Symbol($(string(macrosym))), $(string(ex)), string($expvar)) )
	mtest_macro(ex, paramex, mtestclosureex, macrosym)
end

# mtest_that_sometimes
macro mtest_that_sometimes(ex)
	macrosym = :mtest_that_sometimes
	paramex = :( nothing ) 
	mtestclosureex = :( _s->(any(_s), Symbol($(string(macrosym))), $(string(ex)), "") )
	mtest_macro(ex, paramex, mtestclosureex, macrosym)
end

# mtest_distributed_as
# comparison need not be a Distribution - needs only to permit rand( ,n); a vector would work
# test is that ranksum test against a sample of the same length from the distribution has a p-value above significance level alpha
macro mtest_distributed_as(ex, distex, alphaex)
	macrosym = :mtest_distributed_as
	distvar = gensym(:dist)
	alphavar = gensym(:alpha)
	paramex = :( $distvar = $(esc(distex)); $alphavar = $(esc(alphaex)) )
	mtestclosureex = :( _s->(pvalue(MannWhitneyUTest(convert(Vector{Real},_s), rand($distvar, length(_s)))) > $alphavar,
		 					Symbol($(string(macrosym))), $(string(ex)), string($distvar) * " " * string($alphavar)) )
	mtest_macro(ex, paramex, mtestclosureex, macrosym)
end

end

