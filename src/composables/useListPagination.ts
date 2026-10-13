import { computed, ref, watch, toValue, type MaybeRefOrGetter } from "vue";
import { paginateList } from "@/lib/pagination";
export function useListPagination<T>(items: MaybeRefOrGetter<T[]>, size: number, resetKey: MaybeRefOrGetter<unknown>) {
  const page = ref(1);
  const result = computed(() => paginateList(toValue(items), page.value, size));
  watch(() => toValue(resetKey), () => { page.value = 1; });
  watch(() => result.value.page, value => { page.value = value; });
  return { page, result };
}
