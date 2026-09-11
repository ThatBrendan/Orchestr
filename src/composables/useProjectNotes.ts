import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { useQuery, useMutation, useQueryClient } from "@tanstack/vue-query";
import * as notes from "@/services/projectNotes";
import { qk } from "./keys";

export function useProjectNotes(projectId: MaybeRefOrGetter<string>) {
  const client = useQueryClient();
  const list = useQuery({
    queryKey: computed(() => qk.project.notes(toValue(projectId))),
    queryFn: () => notes.listProjectNotes(toValue(projectId)),
  });
  // Capture the project in mutation variables so navigation cannot invalidate the wrong list.
  const save = useMutation({
    mutationFn: (input: notes.NoteInput & { projectId: string; id?: string }) => input.id
      ? notes.updateProjectNote(input.id, input) : notes.createProjectNote(input.projectId, input),
    onSuccess: (_, input) => client.invalidateQueries({ queryKey: qk.project.notes(input.projectId) }),
  });
  const remove = useMutation({
    mutationFn: (input: { id: string; projectId: string }) => notes.deleteProjectNote(input.id),
    onSuccess: (_, input) => client.invalidateQueries({ queryKey: qk.project.notes(input.projectId) }),
  });
  return { list, save, remove };
}
