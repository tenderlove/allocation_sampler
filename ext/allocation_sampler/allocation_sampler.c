#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>

typedef struct {
    st_table * allocations;
    size_t interval;
    size_t allocation_count;
    VALUE newobj_hook;
} trace_stats_t;

static void
dealloc(void *ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;
    st_free_table(stats->allocations);
    xfree(stats);
}

static int
mark_keys_i(st_data_t key, st_data_t value, void *data)
{
    rb_gc_mark((VALUE)key);
    return ST_CONTINUE;
}

static void
mark(void * ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;
    rb_gc_mark(stats->newobj_hook);
    st_foreach(stats->allocations, mark_keys_i, stats);
}

static const rb_data_type_t trace_stats_type = {
    "ObjectSpace/AllocationSampler",
    {mark, dealloc, 0,},
    0, 0,
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    RUBY_TYPED_FREE_IMMEDIATELY,
#endif
};

static VALUE
user_class(VALUE klass, VALUE obj)
{
    if (RTEST(klass) && !(RB_TYPE_P(obj, T_IMEMO) || RB_TYPE_P(obj, T_NODE)) && BUILTIN_TYPE(klass) == T_CLASS) {
	return rb_class_path_cached(rb_class_real(klass));
    } else {
	return Qnil;
    }
}

static void
newobj(VALUE tpval, void *ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;

    if (!(stats->allocation_count % stats->interval)) {
	rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
	VALUE obj = rb_tracearg_object(tparg);
	VALUE klass = RBASIC_CLASS(obj);
	VALUE uc = user_class(klass, obj);

	if (!NIL_P(uc)) {
	    unsigned long count;
	    if(!st_lookup(stats->allocations, uc, &count)) {
		count = 0;
	    }
	    count++;
	    st_insert(stats->allocations, uc, count);
	}
    }
    stats->allocation_count++;
}

static VALUE
allocate(VALUE klass)
{
    trace_stats_t * stats;
    stats = xmalloc(sizeof(trace_stats_t));
    stats->allocations = st_init_numtable();;
    stats->interval = 1;
    stats->allocation_count = 0;
    stats->newobj_hook = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ, newobj, stats);

    return TypedData_Wrap_Struct(klass, &trace_stats_type, stats);
}

VALUE rb_cAllocationSampler;

static VALUE
enable(VALUE self)
{
    trace_stats_t * stats;
    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);
    rb_tracepoint_enable(stats->newobj_hook);
    return Qnil;
}

static VALUE
disable(VALUE self)
{
    trace_stats_t * stats;
    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);
    rb_tracepoint_disable(stats->newobj_hook);
    return Qnil;
}

static int
insert_to_ruby_hash(st_data_t key, st_data_t value, void *data)
{
    VALUE rb_hash = (VALUE)data;
    rb_hash_aset(rb_hash, (VALUE)key, ULL2NUM((unsigned long)value));
    return ST_CONTINUE;
}

static VALUE
result(VALUE self)
{
    trace_stats_t * stats;
    VALUE result;

    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);

    result = rb_hash_new();
    st_foreach(stats->allocations, insert_to_ruby_hash, result);

    return result;
}

static VALUE
initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE opts;
    VALUE interval;
    trace_stats_t * stats;

    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);
    rb_scan_args(argc, argv, ":", &opts);
    if (!NIL_P(opts)) {
	ID ids[1];
	ids[0] = rb_intern("interval");
	rb_get_kwargs(opts, ids, 0, 1, &interval);
	if (interval != Qundef) {
	    stats->interval = NUM2INT(interval);
	}
    }

    return self;
}

static VALUE
interval(VALUE self)
{
    trace_stats_t * stats;
    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);
    return INT2NUM(stats->interval);
}

void
Init_allocation_sampler(void)
{
    VALUE rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
    rb_cAllocationSampler = rb_define_class_under(rb_mObjSpace, "AllocationSampler", rb_cObject);
    rb_define_alloc_func(rb_cAllocationSampler, allocate);
    rb_define_method(rb_cAllocationSampler, "initialize", initialize, -1);
    rb_define_method(rb_cAllocationSampler, "enable", enable, 0);
    rb_define_method(rb_cAllocationSampler, "disable", disable, 0);
    rb_define_method(rb_cAllocationSampler, "result", result, 0);
    rb_define_method(rb_cAllocationSampler, "interval", interval, 0);
}
