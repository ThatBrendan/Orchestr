import {listItems,listAreas} from '@/services/items';
import {projectCsv,type ExportMember} from '@/lib/projectCsv';
import type {ProjectContextProject} from '@/types/domain';
import type {Commitment} from '@/services/commitments';
export async function downloadProjectCsv(project:ProjectContextProject,_commitments:Commitment[],members:ExportMember[],_currency:string):Promise<void>{
 const [items,areas]=await Promise.all([listItems(project.id),listAreas(project.id)]);
 const csv=projectCsv(project,items,areas,members);
 const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
 const link=document.createElement('a');link.href=url;link.download=(project.name.replace(/[^a-z0-9]+/gi,'-').replace(/^-|-$/g,'')||'project')+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
