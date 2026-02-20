public with sharing class OwnArchiveSdkUtils {
    private static final Integer SUCCESS_STATUS_CODE = 200;
    public static final Map<String,Set<String>> ARCHIVED_OBJECTS_BY_SOBJECT_TYPE = new Map<String,Set<String>>{
            'Contact' => new Set<String>(),
            'Account' => new Set<String>()
    };
    public static final Map<String,Map<String, String>> SOBJECT_FIELD_BY_ARCHIVED_OBJECT = new Map<String,Map<String, String>>{
            'Contact' => new Map<String, String>(),
            'Account' => new Map<String, String>()
    };
    static {
        for (OwnArchiveObjectMappingConfig__mdt config : OwnArchiveObjectMappingConfig__mdt.getAll().values()) {
            ARCHIVED_OBJECTS_BY_SOBJECT_TYPE.get(config.LookupObject__c).add(config.ObjectApiName__c);
            SOBJECT_FIELD_BY_ARCHIVED_OBJECT.get(config.LookupObject__c).put(config.ObjectApiName__c, config.FieldApiName__c);
        }
    }

    public static List<Bulk_Merge_Upload__c> processBulkMergeUploads(List<Bulk_Merge_Upload__c> records, Boolean unarchiveRelatedRecords) {
        List<Bulk_Merge_Upload__c> bulkMergeUploadsWithoutArchivedRecords = new List<Bulk_Merge_Upload__c>();
        if (!records.isEmpty()) {
            for (Bulk_Merge_Upload__c record : records) {
                switch on record.Entity__c {
                    when 'Contact' {
                        bulkMergeUploadsWithoutArchivedRecords.addAll(processContactBulkMergeUploads(records, unarchiveRelatedRecords));
                    }
                    when 'Account' {
                        bulkMergeUploadsWithoutArchivedRecords.addAll(processAccountBulkMergeUploads(records, unarchiveRelatedRecords));
                    }
                }
            }
        }
        return bulkMergeUploadsWithoutArchivedRecords;
    }

    public static List<Bulk_Merge_Upload__c> processAccountBulkMergeUploads(List<Bulk_Merge_Upload__c> records, Boolean unarchiveRelatedRecords) {
        List<Bulk_Merge_Upload__c> bulkMergeUploadsWithoutArchivedRecords = new List<Bulk_Merge_Upload__c>();
        Map<String,Account> nonSurvivingAccountByMemberId = new Map<String, Account>();
        for (Bulk_Merge_Upload__c record : records) {
            if (record.Non_Surviving_Member_ID__c != null) {
                nonSurvivingAccountByMemberId.put(record.Non_Surviving_Member_ID__c, new Account());
            }
            if (record.Non_Surviving_Member_ID2__c != null) {
                nonSurvivingAccountByMemberId.put(record.Non_Surviving_Member_ID2__c, new Account());
            }
        }
        for (Account acc : [SELECT Id,MemberID__c FROM Account WHERE MemberID__c IN :nonSurvivingAccountByMemberId.keySet()]) {
            nonSurvivingAccountByMemberId.put(acc.MemberID__c, acc);
        }
        for (String memberId : nonSurvivingAccountByMemberId.keySet()) {
            if (nonSurvivingAccountByMemberId.get(memberId).Id == null) {
                nonSurvivingAccountByMemberId.remove(memberId);
            }
        }
        for (Bulk_Merge_Upload__c record : records) {
            List<Account> accountToUnarchive = new List<Account>();
            if (nonSurvivingAccountByMemberId.get(record.Non_Surviving_Member_ID__c) != null) {
                accountToUnarchive.add(nonSurvivingAccountByMemberId.get(record.Non_Surviving_Member_ID__c));
            }
            if (nonSurvivingAccountByMemberId.get(record.Non_Surviving_Member_ID2__c) != null) {
                accountToUnarchive.add(nonSurvivingAccountByMemberId.get(record.Non_Surviving_Member_ID2__c));
            }

            if (!accountToUnarchive.isEmpty() && accountToUnarchive != null) {
                OwnArchiveSdkUtils.ArchivedSdkSearchInfo archivedInfo = OwnArchiveSdkUtils.checkArchivedRecords(accountToUnarchive);
                if (archivedInfo.isIntegrationStatusSuccessful) {
                    if (archivedInfo.totalArchivedRecordsOfEachType > 0) {
                        //perform unarchive and do not add to merge list
                        if (unarchiveRelatedRecords) {
                            OwnArchiveSdkUtils.UnarchiveInfo unarchiveInfo = OwnArchiveSdkUtils.performUnarchive(archivedInfo);
                        }
                    } else if (archivedInfo.totalArchivedRecordsOfEachType == 0) { //add BulkMergeUpload records to ready-to-merge list, there is no Archived records in Own Archive database
                        bulkMergeUploadsWithoutArchivedRecords.add(record);
                    }
                }
            }
        }

        return bulkMergeUploadsWithoutArchivedRecords;
    }

    public static List<Bulk_Merge_Upload__c> processContactBulkMergeUploads(List<Bulk_Merge_Upload__c> records, Boolean unarchiveRelatedRecords) {
        List<Bulk_Merge_Upload__c> bulkMergeUploadsWithoutArchivedRecords = new List<Bulk_Merge_Upload__c>();

        Map<String,Contact> nonSurvivingContactByMemberId = new Map<String, Contact>();
        for (Bulk_Merge_Upload__c record : records) {
            if (record.Non_Surviving_Member_ID__c != null) {
                nonSurvivingContactByMemberId.put(record.Non_Surviving_Member_ID__c, new Contact());
            }
            if (record.Non_Surviving_Member_ID2__c != null) {
                nonSurvivingContactByMemberId.put(record.Non_Surviving_Member_ID2__c, new Contact());
            }
        }
        for (Contact con : [SELECT Id,MemberID__c FROM Contact WHERE MemberID__c IN :nonSurvivingContactByMemberId.keySet()]) {
            nonSurvivingContactByMemberId.put(con.MemberID__c, con);
        }
        for (String memberId : nonSurvivingContactByMemberId.keySet()) {
            if (nonSurvivingContactByMemberId.get(memberId).Id == null) {
                nonSurvivingContactByMemberId.remove(memberId);
            }
        }
        for (Bulk_Merge_Upload__c record : records) {
            List<Contact> contactsToUnarchive = new List<Contact>();
            if (nonSurvivingContactByMemberId.get(record.Non_Surviving_Member_ID__c) != null) {
                contactsToUnarchive.add(nonSurvivingContactByMemberId.get(record.Non_Surviving_Member_ID__c));
            }
            if (nonSurvivingContactByMemberId.get(record.Non_Surviving_Member_ID2__c) != null) {
                contactsToUnarchive.add(nonSurvivingContactByMemberId.get(record.Non_Surviving_Member_ID2__c));
            }

            if (!contactsToUnarchive.isEmpty() && contactsToUnarchive != null) {
                OwnArchiveSdkUtils.ArchivedSdkSearchInfo archivedInfo = OwnArchiveSdkUtils.checkArchivedRecords(contactsToUnarchive);
                if (archivedInfo.isIntegrationStatusSuccessful) {
                    if (archivedInfo.totalArchivedRecordsOfEachType > 0) {
                        //perform unarchive and do not add to merge list
                        if (unarchiveRelatedRecords) {
                            OwnArchiveSdkUtils.UnarchiveInfo unarchiveInfo = OwnArchiveSdkUtils.performUnarchive(archivedInfo);
                        }
                    } else if (archivedInfo.totalArchivedRecordsOfEachType == 0) { //add BulkMergeUpload records to ready-to-merge list, there is no Archived records in Own Archive database
                        bulkMergeUploadsWithoutArchivedRecords.add(record);
                    }
                }
            }
        }

        return bulkMergeUploadsWithoutArchivedRecords;
    }

    public static ArchivedSdkSearchInfo checkArchivedRecords(List<SObject> sObjects) {
        System.debug('CheckRecords: '+sObjects);
        ArchivedSdkSearchInfo info = new ArchivedSdkSearchInfo();
        List<Id> sObjectIds = new List<Id>();
        for (SObject obj : sObjects) {
            sObjectIds.add(obj.Id);
        }
        info.searchIds = sObjectIds;

        if (!sObjectIds.isEmpty()) {
            String objectNameById = sObjectIds[0].getSobjectType().getDescribe().getName();
            for (String obj : ARCHIVED_OBJECTS_BY_SOBJECT_TYPE.get(objectNameById)) {
                OB_Archiver.ArchiverAccessorResponse response = callArchiveSearchForObject(obj,sObjectIds);
                if (response.getStatusCode() == SUCCESS_STATUS_CODE) {
                    info.ObjectInfo.add(new ArchivedSingleObjectInfo(response, obj)); //know issue - Archiver SDK Multiple Search method is returning no records : https://help.salesforce.com/s/issue?id=a02Ka00000hDk2d
                } else {
                    System.debug(response.getErrorMessage());
                }
            }
        }

        return info.summarize();
    }

    //know issue - Archiver SDK Multiple Search method is returning no records : https://help.salesforce.com/s/issue?id=a02Ka00000hDk2d - as workaround this method was replaced by similar method with single searchId as parameter instead of array of searchIds
    private static OB_Archiver.ArchiverAccessorResponse callArchiveSearchForObject(String sobjectName, List<Id> searchIds) {
        System.debug('call archive sdk');
        String objectNameById = searchIds[0].getSobjectType().getDescribe().getName();
        List<OB_Archiver.SearchFilter> request = new List<OB_Archiver.SearchFilter>();
        OB_Archiver.SearchFilter filter = new OB_Archiver.SearchFilter(SOBJECT_FIELD_BY_ARCHIVED_OBJECT.get(objectNameById).get(sobjectName), new List<Id>(searchIds));
        request.add(filter);
        return OB_Archiver.ArchiverAccessor.performArchiverGlobalSearch(sobjectName, request);
    }
//search method with single string search param - no longer needed if know issue is resolved https://help.salesforce.com/s/issue?id=a02Ka00000hDk2d
//    private static OB_Archiver.ArchiverAccessorResponse callArchiveSearchForObject(String sobjectName, Id searchId) {
//        String objectNameById = searchId.getSobjectType().getDescribe().getName();
//        List<OB_Archiver.SearchFilter> request = new List<OB_Archiver.SearchFilter>();
//        OB_Archiver.SearchFilter filter = new OB_Archiver.SearchFilter(SOBJECT_FIELD_BY_ARCHIVED_OBJECT.get(objectNameById).get(sobjectName), searchId);
//        request.add(filter);
//        return OB_Archiver.ArchiverAccessor.performArchiverGlobalSearch(sobjectName, request);
//    }

    @InvocableMethod
    public static void performUnarchiveInvocable(List<FlowParams> params) {
        if (!params.isEmpty()) {
            Map<String,Set<Id>> incomingIdsByType = new Map<String, Set<Id>>();

            for (FlowParams param : params) {
                if (incomingIdsByType.containsKey(param.sobjectTypeName)) {
                    incomingIdsByType.get(param.sobjectTypeName).add(param.recordId);
                } else {
                    incomingIdsByType.put(param.sobjectTypeName, new Set<Id>{param.recordId});
                }
            }
            for (String objectName : incomingIdsByType.keySet()){
                OwnArchiveSdkUtils.ArchivedSdkSearchInfo archivedInfo = new OwnArchiveSdkUtils.ArchivedSdkSearchInfo();
                archivedInfo.searchIds = new List<Id>(incomingIdsByType.get(objectName));
                archivedInfo.archivedTypes = new List<String>(ARCHIVED_OBJECTS_BY_SOBJECT_TYPE.get(objectName));
                OwnArchiveSdkUtils.UnarchiveInfo info = new OwnArchiveSdkUtils.UnarchiveInfo(archivedInfo);
                String objectNameById = archivedInfo.searchIds[0].getSobjectType().getDescribe().getName();
                for (String archivedType : archivedInfo.archivedTypes) {
                    List<OB_Archiver.SearchFilter> request = new List<OB_Archiver.SearchFilter>();
                    OB_Archiver.SearchFilter filter = new OB_Archiver.SearchFilter(SOBJECT_FIELD_BY_ARCHIVED_OBJECT.get(objectName).get(archivedType), archivedInfo.searchIds);
                    request.add(filter);
                    OB_Archiver.ArchiverAccessorResponse response = OB_Archiver.ArchiverAccessor.performUnarchiveSdk(archivedType, request);
                    info.responses.add(response);
                }
            }
        }
    }

    public class FlowParams {
        @InvocableVariable(Label='Record ID' Required=true)
        public String recordId;

        @InvocableVariable(Label='SobjectType' Required=true)
        public String sobjectTypeName;
    }

    public static SObject checkArchiveInfoForSobject(SObject record) {
        try {
            record.put('Merge_Process_Status__c', 'Archive Check In Progress');
            OwnArchiveSdkUtils.ArchivedSdkSearchInfo archivedInfo = OwnArchiveSdkUtils.checkArchivedRecords(new List<SObject>{record});
            if (archivedInfo.isIntegrationStatusSuccessful && archivedInfo.totalArchivedRecordsOfEachType > 0) {
                //call for Unarchive related records and prevent merge
                OwnArchiveSdkUtils.UnarchiveInfo unarchiveInfo = OwnArchiveSdkUtils.performUnarchive(archivedInfo);
                record.put('Merge_Process_Status__c', 'Archive Check In Progress');
            } else if (archivedInfo.totalArchivedRecordsOfEachType == 0) { //records to ready-to-merge status, there is no Archived records in Own Archive database
                record.put('Merge_Process_Status__c', 'Ready for Merge');
            }
        } catch (Exception e) {
            System.debug('Error updating Merge_Process_Status__c: ' + e.getMessage());
        }
        return record;
    }

    public static UnarchiveInfo performUnarchive(ArchivedSdkSearchInfo archivedInfo) {
        UnarchiveInfo info = new UnarchiveInfo(archivedInfo);
        String objectNameById = archivedInfo.searchIds[0].getSobjectType().getDescribe().getName();
        for (String objectName : archivedInfo.archivedTypes) {
            List<OB_Archiver.SearchFilter> request = new List<OB_Archiver.SearchFilter>();
            OB_Archiver.SearchFilter filter = new OB_Archiver.SearchFilter(SOBJECT_FIELD_BY_ARCHIVED_OBJECT.get(objectNameById).get(objectName), archivedInfo.searchIds);
            request.add(filter);
            OB_Archiver.ArchiverAccessorResponse response = OB_Archiver.ArchiverAccessor.performUnarchiveSdk(objectName, request);
            info.responses.add(response);
        }
        return info;
    }

    public class UnarchiveInfo {
        public List<OB_Archiver.ArchiverAccessorResponse> responses;
        public List<Id> searchIds;
        public List<String> archivedTypes;

        public UnarchiveInfo(ArchivedSdkSearchInfo searchInfo) {
            this.searchIds = searchInfo.searchIds;
            this.archivedTypes = searchInfo.archivedTypes;
            this.responses = new List<OB_Archiver.ArchiverAccessorResponse>();
        }
    }

    public class ArchivedSdkSearchInfo {
        public Boolean isIntegrationStatusSuccessful = true;
        public List<ArchivedSingleObjectInfo> ObjectInfo;
        public List<String> archivedTypes;
        public String archivedTypesString;
        public Integer totalArchivedRecordsOfEachType;
        public List<Id> searchIds;

        public ArchivedSdkSearchInfo() {
            this.ObjectInfo = new List<ArchivedSingleObjectInfo>();
        }

        public ArchivedSdkSearchInfo summarize() {
            List<String> archivedTypes = new List<String>();
            Integer totalRecords = 0;
            if (!this.ObjectInfo.isEmpty()) {
                for (ArchivedSingleObjectInfo singleObjectInfo : ObjectInfo) {
                    if (singleObjectInfo.responseStatusCode != SUCCESS_STATUS_CODE) {
                        this.isIntegrationStatusSuccessful = false;
                    }
                    archivedTypes.add(singleObjectInfo.objectName);
                    totalRecords += singleObjectInfo.totalResults;
                }
            }
            this.totalArchivedRecordsOfEachType = totalRecords;
            this.archivedTypes = archivedTypes;
            this.archivedTypesString = archivedTypes.toString();
            System.debug('Types: '+ this.archivedTypes+ ' IntegrationSuccessful?  : '+this.isIntegrationStatusSuccessful+'  totalRecordsfound: '+this.totalArchivedRecordsOfEachType);
            return this;
        }
    }

    public class ArchivedSingleObjectInfo {
        public OB_Archiver.ArchiverAccessorResponse response;
        public Map<String,Object> responseMap;
        public String objectName;
        public Integer totalResults;
        public Integer responseStatusCode;

        public ArchivedSingleObjectInfo(OB_Archiver.ArchiverAccessorResponse response, String objectName) {
            this.responseStatusCode = response.getStatusCode();
            if (this.responseStatusCode == SUCCESS_STATUS_CODE) {
                this.responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                this.totalResults = (Integer)responseMap.get('total_result_count');
            }
            this.response = response;
            this.objectName = objectName;
        }
    }
}