<script setup lang="ts">
import { computed, ref } from 'vue';
import { useQuery } from '@tanstack/vue-query';
import { useAuthStore } from '@/stores/auth';
import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
import { notificationCategories, type NotificationCategory } from '@/lib/notificationRegistry';
const auth = useAuthStore();
const busy = ref(false), error = ref('');
const query = useQuery({
  queryKey: computed(() => ['notification-preferences', auth.userId]),
  enabled: computed(() => auth.isAuthenticated),
  queryFn: async () => {
    const { data, error } = await supabase.from('user_notification_preferences').select('category,enabled');
    if (error) throw toAppError(error);
    return data;
  },
});
function enabled(category: string) { return !query.data.value?.some(row => row.category === category && !row.enabled); }
async function toggle(category: NotificationCategory) {
  busy.value = true; error.value = '';
  try {
    const { error: failure } = await supabase.rpc('set_my_notification_preference', { p_category: category, p_enabled: !enabled(category) });
    if (failure) throw toAppError(failure);
    await query.refetch();
  } catch (e) { error.value = toAppError(e).message; }
  finally { busy.value = false; }
}
</script>
<template>
  <section
    class="mt-8 border-t border-line pt-6 space-y-4"
    aria-labelledby="notification-preferences-title"
  >
    <h2
      id="notification-preferences-title"
      class="text-section-heading font-semibold"
    >
      Notifications
    </h2>
    <p class="text-meta text-muted">
      Choose optional in-app updates across your projects. Essential workflow updates always arrive.
    </p>
    <p
      v-if="query.isPending.value"
      role="status"
    >
      Loading preferences…
    </p>
    <p
      v-else-if="query.isError.value"
      role="alert"
    >
      Could not load preferences. <button
        class="inline-flex min-h-11 items-center rounded-lg underline focus-ring"
        @click="query.refetch()"
      >
        Retry
      </button>
    </p>
    <template v-else>
      <label
        v-for="category in notificationCategories"
        :key="category.id"
        class="min-h-11 flex items-center gap-4 justify-between"
      >
        <span><span class="block font-medium">{{ category.label }}</span><span class="block text-meta text-muted">{{ category.description }}</span></span>
        <input
          type="checkbox"
          class="h-5 w-5 shrink-0 focus-ring"
          :aria-label="category.label"
          :checked="enabled(category.id)"
          :disabled="busy"
          @change="toggle(category.id)"
        >
      </label>
    </template>
    <p
      v-if="error"
      role="alert"
      class="text-danger"
    >
      {{ error }}
    </p>
  </section>
</template>
