<script setup lang="ts">
import { useMyProfile } from "@/composables/useDashboard";
import PageContainer from "@/components/ui/PageContainer.vue";
import SkeletonBlock from "@/components/ui/SkeletonBlock.vue";
import FeaturePending from "@/components/ui/FeaturePending.vue";

const { profile, isPending } = useMyProfile();

const notif = (raw: unknown) => {
  if (!raw || typeof raw !== "object") return "—";
  const p = raw as Record<string, unknown>;
  const on = [p.email ? "Email" : null, p.push ? "Push" : null].filter(Boolean);
  return on.length ? on.join(" + ") : "Off";
};
</script>

<template>
  <PageContainer width="md">
    <h1 class="font-display text-[26px] font-semibold tracking-tight">Settings</h1>
    <p class="mt-1.5 text-14.5 text-ink-soft">Manage your account and preferences.</p>

    <div class="mt-8 space-y-2">
      <SkeletonBlock v-if="isPending" height="180px" rounded="0.75rem" />
      <div v-else class="border rounded-xl divide-y border-line bg-surface">
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Name</span>
          <span class="text-14">{{ profile?.display_name ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Email</span>
          <span class="text-14">{{ profile?.email ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Timezone</span>
          <span class="text-14">{{ profile?.timezone ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Currency</span>
          <span class="text-14">{{ profile?.default_currency ?? "—" }}</span>
        </div>
        <div class="flex items-center justify-between px-5 py-4">
          <span class="text-14 font-medium text-ink-soft">Notifications</span>
          <span class="text-14">{{ notif(profile?.notification_prefs) }}</span>
        </div>
      </div>
    </div>

    <div class="mt-4">
      <FeaturePending
        title="Editing your profile"
        detail="These values are live from your account. In-app editing arrives in a later pass."
      />
    </div>
  </PageContainer>
</template>
