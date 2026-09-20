<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useProjectJoin } from "@/composables/useProjectJoin";
import AuthPage from "@/components/ui/AuthPage.vue";
import AppButton from "@/components/ui/AppButton.vue";
const route = useRoute();
const token = computed(() => String(route.params.token));
const { state, loading, sending, error, refresh, request } = useProjectJoin(token);
const continuation = computed(() => ({ redirect: `/join/${token.value}` }));
</script>
<template>
  <AuthPage title="Join a project">
    <p
      v-if="loading"
      role="status"
      class="text-14"
    >
      Checking join link…
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-14 text-danger"
    >
      {{ error }}
    </p>
    <div
      v-if="!loading"
      class="space-y-4 text-14"
    >
      <template v-if="state?.state === 'sign_in'">
        <p>You've been invited to join a project on Orchestrio. Sign in or create an account to request access.</p>
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
      <template v-else-if="state?.state === 'eligible'">
        <p>Request access to collaborate on this project.</p>
        <AppButton
          :loading="sending"
          :aria-busy="sending"
          block
          @click="request"
        >
          Request access
        </AppButton>
      </template>
      <template v-else-if="state?.state === 'pending'">
        <p role="status">
          Your access request is pending approval.
        </p>
        <AppButton
          variant="secondary"
          block
          @click="refresh"
        >
          Check status
        </AppButton>
      </template>
      <template v-else-if="state?.state === 'member'">
        <p>You're already a member of this project.</p>
        <AppButton
          :to="{ name: 'project.overview', params: { projectId: state.project_id } }"
          block
        >
          Open project
        </AppButton>
      </template>
      <p v-else-if="state?.state === 'unavailable'">
        This join link is no longer available.
      </p>
      <AppButton
        v-else
        variant="secondary"
        @click="refresh"
      >
        Retry
      </AppButton>
    </div>
  </AuthPage>
</template>
