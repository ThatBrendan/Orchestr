import {commitmentStatusLabel} from './activityWorkflows';
import { userFacingActivityStatus } from './presentation';
import type {ActivityType} from '@/types/database';
export function itemTypeLabel(type:string){return ({task:'Task',event:'Event',booking:'Booking',purchase:'Purchase',other:'Other'} as Record<string,string>)[type]??'Other';}
export function itemStatusLabel(item:{source:string;status:string;item_type:string}) {
 if(item.source==='task')return userFacingActivityStatus(item.status);
 return commitmentStatusLabel(item.item_type as ActivityType,item.status as Parameters<typeof commitmentStatusLabel>[1]);
}
