#include <ruby/ruby.h>

typedef struct alloc_info {
    VALUE klass;
} alloc_info_t;

typedef struct {
    size_t alloc_capa;
    size_t alloc_next_free;
    alloc_info_t ** alloc_list;
} trace_stats_t;

static VALUE allocate(VALUE klass)
{
    trace_stats_t * stats;
    stats->alloc_capa = 1000;
    stats->alloc_next_free = 0;
    stats->alloc_list = xmalloc(sizeof(alloc_info) * stats->alloc_capa);

    stats = xmalloc(sizeof(trace_stats_t));
    return TypedData_Make_Struct(klass, trace_stats_t, &trace_stats_type, stats);
}

static void dealloc(void *ptr)
{
    xfree(stats->alloc_list);
    xfree(ptr);
}

static const rb_data_type_t trace_stats_type = {
    "ObjectSpace/AllocationSampler",
    {0, dealloc, 0,},
    0, 0,
#ifdef RUBY_TYPED_FREE_IMMEDIATELY
    RUBY_TYPED_FREE_IMMEDIATELY,
#endif
};

VALUE rb_cAllocationSampler;


void
Init_allocation_sampler(void)
{
    VALUE rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
    rb_cAllocationSampler = rb_define_class_under(rb_mObjSpace, "AllocationSampler");
    rb_define_alloc_func(rb_cAllocationSampler, allocate);
}
