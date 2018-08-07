#include <ruby/ruby.h>
#include <ruby/debug.h>
#include <ruby/st.h>

typedef struct alloc_info {
    VALUE klass;
} alloc_info_t;

typedef struct {
    size_t alloc_capa;
    size_t alloc_next_free;
    alloc_info_t * alloc_list;
    VALUE newobj_hook;
} trace_stats_t;

static void
dealloc(void *ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;
    xfree(stats->alloc_list);
    xfree(stats);
}

static void
mark(void * ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;
    size_t i;
    rb_gc_mark(stats->newobj_hook);

    alloc_info_t * info = stats->alloc_list;
    for(i = 0; i < stats->alloc_next_free; i++, info++) {
	rb_gc_mark(info->klass);
    }
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
    if (RTEST(klass) && !RB_TYPE_P(obj, T_NODE)) {
	return rb_class_real(klass);
    } else {
	return Qnil;
    }
}

static void
newobj(VALUE tpval, void *ptr)
{
    trace_stats_t * stats = (trace_stats_t *)ptr;
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    VALUE obj = rb_tracearg_object(tparg);
    VALUE klass = RBASIC_CLASS(obj);
    VALUE uc = user_class(klass, obj);

    alloc_info_t * info = stats->alloc_list + stats->alloc_next_free;
    info->klass = uc;
    stats->alloc_next_free++;
}

static VALUE
allocate(VALUE klass)
{
    trace_stats_t * stats;
    stats = xmalloc(sizeof(trace_stats_t));
    stats->alloc_capa = 1000;
    stats->alloc_next_free = 0;
    stats->alloc_list = xcalloc(stats->alloc_capal, sizeof(alloc_info_t));
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
    rb_p(key);
    rb_hash_aset(rb_hash, (VALUE)key, ULL2NUM((unsigned long)value));
    return ST_CONTINUE;
}

static VALUE
result(VALUE self)
{
    trace_stats_t * stats;
    size_t i;
    VALUE result;

    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);

    st_table * aggregate = st_init_numtable_with_size(stats->alloc_next_free);
    result = rb_hash_new();

    alloc_info_t * info = stats->alloc_list;
    for(i = 0; i < stats->alloc_next_free; i++, info++) {
	/* Count needs to be wide enough so `st_lookup` doesn't clobber `info` */
	unsigned long count;
	if(!st_lookup(aggregate, info->klass, &count)) {
	    count = 0;
	}
	count++;
	st_insert(aggregate, info->klass, count);
    }
    st_foreach(aggregate, insert_to_ruby_hash, result);

    return result;
}

static VALUE
record_count(VALUE self)
{
    trace_stats_t * stats;
    TypedData_Get_Struct(self, trace_stats_t, &trace_stats_type, stats);
    return INT2NUM(stats->alloc_next_free);
}

void
Init_allocation_sampler(void)
{
    VALUE rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
    rb_cAllocationSampler = rb_define_class_under(rb_mObjSpace, "AllocationSampler", rb_cObject);
    rb_define_alloc_func(rb_cAllocationSampler, allocate);
    rb_define_method(rb_cAllocationSampler, "enable", enable, 0);
    rb_define_method(rb_cAllocationSampler, "disable", disable, 0);
    rb_define_method(rb_cAllocationSampler, "result", result, 0);
    rb_define_method(rb_cAllocationSampler, "record_count", record_count, 0);
}
