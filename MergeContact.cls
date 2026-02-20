public class MergeContact {
    @TestVisible private static final String FAILED_MERGE_STATUS = 'Fail Merge';
    private static final String IAPL_PARTNER_COMMUNITY_USER_PROFILE = 'IAPL-Partner Community User';

    public static Map<String,String> MergeContactIntoMaster(List<Bulk_Merge_Upload__c> records) {
        Map<String, String> netExamMergeMap = new Map<String,String>();
        Set<String> allMemberIds = new Set<String>();
        for (Bulk_Merge_Upload__c record: records){
            if (!String.isBlank(record.Surviving_Member_ID__c)){
                allMemberIds.add(record.Surviving_Member_ID__c);
            }

            if (!String.isBlank(record.Non_Surviving_Member_ID__c)){
                allMemberIds.add(record.Non_Surviving_Member_ID__c);
            }

            if (!String.isBlank(record.Non_Surviving_Member_ID2__c)){
                allMemberIds.add(record.Non_Surviving_Member_ID2__c);
            }
        }

        Map<String, Contact> contactByMemberId = getContactByMemberId(allMemberIds);
        Map<Id, OrderApi__Badge__c> contact2Badge = getBadges(contactByMemberId.values());
        Map<Id, User> iaplUsersByContactId = getPartnerCommunityUsersByContactId(contactByMemberId.values());
        for(Bulk_Merge_Upload__c record: records){
            List<Contact> duplicates = new List<Contact>();
            List<String> failReasons = new List<String>();
            try{
                Contact master = contactByMemberId.get(record.Surviving_Member_ID__c);
                Contact c = contactByMemberId.get(record.Non_Surviving_Member_ID__c);

                if (c != null) {
                    if (iaplUsersByContactId.containsKey(c.Id)) {
                        failReasons.add('ID1: Prevent Merge: Non-surviving Contact is a IAPL Partner Community User');
                    } else {
                        MergeValidationResult res = isMergeable(c, contact2Badge);
                        if (res.isValid) {
                            duplicates.add(c);
                        } else {
                            failReasons.add('ID1: '+res.reason);
                        }
                    }
                }
                if (!String.isBlank(record.Non_Surviving_Member_ID2__c)) {
                    Contact c1 = contactByMemberId.get(record.Non_Surviving_Member_ID2__c);
                    if (c1 != null && iaplUsersByContactId.containsKey(c1.Id)) {
                        failReasons.add('ID1: Prevent Merge: Non-surviving Contact is a IAPL Partner Community User');
                    } else if (c1 != null) {
                        MergeValidationResult res2 = isMergeable(c1, contact2Badge);
                        if (res2.isValid) {
                            duplicates.add(c1);
                        } else {
                            failReasons.add('ID2: '+ res2.reason);
                        }
                    }
                }

                Boolean anyFail = !failReasons.isEmpty();
                Boolean noCandidates = duplicates.isEmpty();

                if (anyFail || noCandidates) {
                    record.Status__c = FAILED_MERGE_STATUS;
                    record.Fail_Merge_Reason__c = String.join(failReasons, ' | ');
                    continue;
                }

                if (master.IAPL_Owner__c == null) {
                    for (Contact dup : duplicates) {
                        if (dup.IAPL_Owner__c != null) {
                            master.IAPL_Owner__c = dup.IAPL_Owner__c;
                            System.debug('Transferring IAPL_Owner__c value from non-surviving record ' + dup.Id + ': ' + dup.IAPL_Owner__c);
                            break;
                        }
                    }
                } else {
                    System.debug('Master record already has IAPL_Owner__c value: ' + master.IAPL_Owner__c);
                }
                deleteRedundantAccountContactRelations(master.Id, duplicates);

                Database.MergeResult[] results = Database.merge(master, duplicates, true);

                for(Database.MergeResult res : results) {
                    if (res.isSuccess()) {
                        String source = (String) duplicates.get(0).Id;
                        String destination = (String) master.Id;
                        if (source != null && destination != null) {
                            netExamMergeMap.put(source, destination);
                        }
                        List<Id> mergedIds = res.getMergedRecordIds();
                        if(record.Status__c != FAILED_MERGE_STATUS){
                            record.Status__c = 'Complete Merge';
                        }
                    } else {
                        record.Status__c = FAILED_MERGE_STATUS;
                        for(Database.Error err : res.getErrors()) {
                            System.debug(err.getMessage());
                            record.Fail_Merge_Reason__c = record.Fail_Merge_Reason__c +':'+err.getMessage();
                        }
                    }
                }
            }

            catch(Exception e){
                System.debug(e);
                record.Status__c = FAILED_MERGE_STATUS;
                record.Fail_Merge_Reason__c = e.getMessage();
            }
        }
        update records;
        return netExamMergeMap;
    }

    private static Map<Id, User> getPartnerCommunityUsersByContactId(List<Contact> contacts) {
        Map<Id, User> result = new Map<Id, User>();
        if (contacts == null || contacts.isEmpty()) {
            return result;
        }

        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        List<User> partnerUsers = [
                SELECT Id, ContactId, Profile.Name
                FROM User
                WHERE ContactId IN :contactIds
                AND Profile.Name = :IAPL_PARTNER_COMMUNITY_USER_PROFILE
                AND IsActive = true
        ];

        for (User u : partnerUsers) {
            result.put(u.ContactId, u);
        }

        return result;
    }

    private static void deleteRedundantAccountContactRelations(Id masterContactId, List<Contact> mergedRecordList) {
        Set<Id> allContactIds = new Set<Id>{masterContactId};
        for (Contact obj : mergedRecordList) {
            allContactIds.add(obj.Id);
        }

        List<AccountContactRelation> allACRs = [
                SELECT Id, ContactId, AccountId, IsDirect
                FROM AccountContactRelation
                WHERE ContactId IN :allContactIds
        ];

        Set<Id> masterAccountIds = new Set<Id>();
        for (AccountContactRelation acr : allACRs) {
            if (acr.ContactId == masterContactId) {
                masterAccountIds.add(acr.AccountId);
            }
        }

        List<AccountContactRelation> acrsToDelete = new List<AccountContactRelation>();
        for (AccountContactRelation acr : allACRs) {
            if (acr.ContactId != masterContactId && masterAccountIds.contains(acr.AccountId) && !acr.IsDirect) {
                acrsToDelete.add(acr);
            }
        }
        if (!acrsToDelete.isEmpty()) {
            System.debug('Deleting ' + acrsToDelete.size() + ' redundant AccountContactRelation records before Contact merge');
            delete acrsToDelete;
        }
    }

    private static MergeValidationResult isMergeable(Contact contact, Map<Id, OrderApi__Badge__c> contact2Badge) {
        if (contact == null) {
            return new MergeValidationResult(false, 'Contact not found');
        }

        if (contact.CTS_Designation__c != null) {
            return new MergeValidationResult(false, 'Non Surviving MemberID Has CTS');
        }

        if (contact.Member_Type__c == 'Premium' || contact.Member_Type__c == 'Student Member') {
            return new MergeValidationResult(false, 'Non Surviving MemberID Has Individual Membership');
        }

        if (contact.Member_Type__c == 'Elite') {
            Boolean hasEnterpriseBadge = contact2Badge.get(contact.Id)?.Badge_Type_Name__c == 'Enterprise Elite Badge';
            if (!hasEnterpriseBadge) {
                return new MergeValidationResult(false, 'Elite Member without Enterprise Elite Badge');
            }
        }

        if (!String.isBlank(contact.MYS_Id__c)) {
            return new MergeValidationResult(false, 'Contact has restricted value in MYS_Id__c field');
        }

        if (contact.PearsonCandiateId__c != null) {
            return new MergeValidationResult(false, 'Contact has restricted value in PearsonCandiateId__c field');
        }

        return new MergeValidationResult(true, null);
    }

    private static Map<String, Contact> getContactByMemberId(Set<String> memberIds){
        List<Contact> contactsForMemberIds =[
                SELECT
                        Id,
                        MemberID__c,
                        CTS_Designation__c,
                        Member_Type__c,
                        PearsonCandiateId__c,
                        MYS_Id__c,
                        IAPL_Owner__c
                FROM Contact
                WHERE MemberID__c IN :memberIds
        ];

        Map<String, Contact> contactByMemberId = new Map<String, Contact>();

        if (contactsForMemberIds != null && !contactsForMemberIds.isEmpty()){
            for (Contact contact : contactsForMemberIds){
                contactByMemberId.put(contact.MemberID__c, contact);
            }
        }
        return contactByMemberId;
    }

    @TestVisible
    private static Map<Id, OrderApi__Badge__c> getBadges(List<Contact> contacts){
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        List<OrderApi__Badge__c> badges = [
                SELECT
                        Id, OrderApi__Contact__c, OrderApi__Is_Active__c, Badge_Type_Name__c
                FROM OrderApi__Badge__c
                WHERE OrderApi__Contact__c IN :contactIds AND OrderApi__Is_Active__c = TRUE AND Badge_Type_Name__c = 'Enterprise Elite Badge'
        ];
        Map<Id, OrderApi__Badge__c> contactId2Badge = new Map<Id, OrderApi__Badge__c>();
        if(!badges.isEmpty()){
            for (OrderApi__Badge__c badge : badges) {
                contactId2Badge.put(badge.OrderApi__Contact__c, badge);
            }
        }
        return contactId2Badge;
    }

    private class MergeValidationResult {
        public Boolean isValid { get; set; }
        public String reason { get; set; }

        public MergeValidationResult(Boolean isValid, String reason) {
            this.isValid = isValid;
            this.reason = reason;
        }
    }
}