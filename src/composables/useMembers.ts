import { useMutation, useQueryClient } from "@tanstack/vue-query";
import { qk } from "./keys";
import * as members from "@/services/members";
import type { MemberRole } from "@/types/database";

export function useInviteMember(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { email: string; role: Extract<MemberRole, "member" | "viewer"> }) =>
      members.inviteMember(projectId, input.email, input.role),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.members(projectId) });
    },
  });
}

export function useUpdateMemberRole(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (input: { memberId: string; role: MemberRole }) =>
      members.updateMemberRole(input.memberId, input.role),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.members(projectId) });
    },
  });
}

export function useRemoveMember(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (memberId: string) => members.removeMember(memberId),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.members(projectId) });
    },
  });
}

export function useReactivateMember(projectId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (memberId: string) => members.reactivateMember(memberId),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: qk.project.members(projectId) });
    },
  });
}
