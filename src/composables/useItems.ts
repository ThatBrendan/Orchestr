import {computed,toValue,type MaybeRefOrGetter} from 'vue';
import {useQuery} from '@tanstack/vue-query';
import * as items from '@/services/items';
export function useItems(id:MaybeRefOrGetter<string>) {
 return useQuery({queryKey:computed(()=>['project',toValue(id),'items']),queryFn:()=>items.listItems(toValue(id))});
}
export function useAreas(id:MaybeRefOrGetter<string>) {
 return useQuery({queryKey:computed(()=>['project',toValue(id),'areas']),queryFn:()=>items.listAreas(toValue(id))});
}
export function useAreaTotals(id:MaybeRefOrGetter<string>) {
 return useQuery({queryKey:computed(()=>['project',toValue(id),'area-totals']),queryFn:()=>items.areaTotals(toValue(id))});
}
