<script setup lang="ts">
import { computed, onScopeDispose, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { resolveShareToken, type ShareResolution } from "@/services/shareLinks";
import AuthPage from "@/components/ui/AuthPage.vue";
import AppButton from "@/components/ui/AppButton.vue";
const route = useRoute(), router = useRouter(), auth = useAuthStore();
const token = computed(() => String(route.params.token));
const continuation = computed(() => ({ redirect: `/s/${token.value}` }));
const state = ref<ShareResolution>(), loading = ref(false), failed = ref(false);
let generation = 0;
onScopeDispose(() => { generation++; });
async function resolve() {
  const current = ++generation;
  state.value = undefined; loading.value = true; failed.value = false;
  try {
    const result = await resolveShareToken(token.value);
    if (current !== generation) return;
    state.value = result;
    if (result.state === "authorized" && result.resource_type === "activity") {
      // A known internal route only. Normal router guards, Activity APIs and RLS still apply.
      await router.replace({ name: "project.commitments", params: { projectId: result.project_id }, query: { commitment: result.resource_id } });
    }
  } catch { if (current === generation) failed.value = true; }
  finally { if (current === generation) loading.value = false; }
}
watch(() => [token.value, auth.userId, auth.ready], () => { if (auth.ready) void resolve(); }, { immediate: true });
</script>
<template>
  <AuthPage title="Open shared item">
    <p
      v-if="loading"
      role="status"
      class="text-14"
    >
      Checking shared link…
    </p>
    <div
      v-else
      class="space-y-4 text-14"
    >
      <template v-if="state?.state === 'sign_in'">
        <p>Sign in to open this shared item.</p>
        <AppButton
          :to="{ name: 'login', query: continuation }"
          block
        >
          Log in
        </AppButton>
        <AppButton
          :to="{ name: 'signup', query: continuation }"
          variant="secondary"
          block
        >
          Create account
        </AppButton>
      </template>
      <template v-else-if="failed">
        <p role="alert">
          Unable to check this link. Please try again.
        </p>
        <AppButton
          variant="secondary"
          @click="resolve"
        >
          Retry
        </AppButton>
      </template>
      <p v-else>
        This shared item isn't available to your account.
      </p>
    </div>
  </AuthPage>
</template>
