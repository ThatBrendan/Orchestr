import type {Item,Area} from '@/services/items';
import {currencyDigits} from '@/lib/money';
import {itemTypeLabel,itemStatusLabel} from '@/lib/itemPresentation';
import type {ProjectContextProject} from '@/types/domain';
export type ExportMember={member_id:string;display_name:string};
// Quote all cells, preserve CR/LF and neutralize spreadsheet formulas in user text.
export function csvCell(value:string|number|null|undefined):string {
 let text=value==null?'':String(value);
 if(/^[\s]*[=+\-@]/.test(text) && !/^-?\d+(\.\d+)?$/.test(text))text="'"+text;
 return '"'+text.replace(/"/g,'""')+'"';
}
export function projectCsv(project:Pick<ProjectContextProject,'name'|'timezone'|'currency'>,items:Item[],areas:Area[],members:ExportMember[]):string {
 const money=(value:number|null)=>value==null?'':(value/10**currencyDigits(project.currency)).toFixed(currencyDigits(project.currency));
 const rows=[['Project','Category','Activity','Type','Status','Assigned To','Date','Cost','Paid','Outstanding','Currency']];
 for(const item of items)rows.push([project.name,areas.find(a=>a.id===item.area_id)?.title??'',item.title,itemTypeLabel(item.item_type),itemStatusLabel(item),members.find(m=>m.member_id===item.assignee_member_id)?.display_name??'',item.item_date?new Intl.DateTimeFormat('en-GB',{timeZone:project.timezone}).format(new Date(item.item_date)):'',money(item.cost_minor),money(item.paid_minor),money(item.outstanding_minor),project.currency]);
 return '\uFEFF'+rows.map(row=>row.map(csvCell).join(',')).join('\r\n')+'\r\n';
}
