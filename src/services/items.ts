import { supabase } from '@/lib/supabase';
import { toAppError } from '@/lib/errors';
import type { Database, Tables } from '@/types/database';
export type Area = Tables<'project_areas'>;
export type Item = Database['public']['Views']['v_project_items']['Row'];
export async function listAreas(projectId: string) {
 const {data,error}=await supabase.from('project_areas').select('*').eq('project_id',projectId).order('created_at');
 if(error)throw toAppError(error);return data;
}
export async function listItems(projectId:string) {
 const {data,error}=await supabase.from('v_project_items').select('*').eq('project_id',projectId).order('created_at');
 if(error)throw toAppError(error);return data;
}
export async function areaTotals(projectId:string) {
 const {data,error}=await supabase.from('v_area_totals').select('*').eq('project_id',projectId);
 if(error)throw toAppError(error);return data;
}
export async function saveArea(projectId:string,title:string,notes:string,id?:string) {
 const query=id?supabase.from('project_areas').update({title,notes:notes||null}).eq('id',id).eq('project_id',projectId):supabase.from('project_areas').insert({project_id:projectId,title,notes:notes||null});
 const {data,error}=await query.select().single();if(error)throw toAppError(error);return data;
}
export async function deleteArea(id:string) {
 const {data,error}=await supabase.rpc('delete_project_category',{p_category:id});
 if(error)throw toAppError(error);return data;
}
export async function completeAssignedItem(id:string,date?:string) {
 const {error}=await supabase.rpc('complete_assigned_item',{p_item:id,p_occurrence_date:date??null});if(error)throw toAppError(error);
}
