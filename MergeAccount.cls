public class MergeAccount {

    public static void MergeAccountIntoMaster(List<Bulk_Merge_Upload__c> records)
    {

        Set<Id> nonSurvivingAccountIds = new Set<Id>();
        Set<String> survivingMembers = new Set<String>();
        Set<String> nonSurvivingMembers = new Set<String>();
        Set<String> nonSurvivingMembers2 = new Set<String>();
        for(Bulk_Merge_Upload__c record: records){
            survivingMembers.add(record.Surviving_Member_ID__c);
            nonSurvivingMembers.add(record.Non_Surviving_Member_ID__c);
            if(record.Non_Surviving_Member_ID2__c != null ){
                nonSurvivingMembers2.add(record.Non_Surviving_Member_ID2__c);
            }
        }
        Map<String, Account> cs1 = new Map<String, Account>();
        Map<String, Account> masters1 = new Map<String, Account>();
        for(Account objCS : [SELECT Id, MemberID__c,IAPL_Owner__c FROM Account WHERE MemberID__c in :survivingMembers]){
            masters1.put(objCS.MemberID__c, objCS);
        }
        Map<String, Account> masters = new Map<String, Account>();
        for(Account objCS : [SELECT Id, MemberID__c,IsCustomerPortal,Member_Type__c,IAPL_Owner__c FROM Account WHERE MemberID__c in :survivingMembers]){
            masters.put(objCS.MemberID__c, objCS);
        }

        Map<String, Account> cs = new Map<String, Account>();
        for(Account objCS : [SELECT Id, MemberID__c,IsCustomerPortal,Member_Type__c,MYS_Id__c,IAPL_Owner__c FROM Account WHERE MemberID__c in :nonSurvivingMembers]){
            cs.put(objCS.MemberID__c, objCS);
            nonSurvivingAccountIds.add(objCS.Id);
        }
        if(!nonSurvivingMembers2.isEmpty()){
            for(Account objCS : [SELECT Id, MemberID__c,IsCustomerPortal,Member_Type__c,MYS_Id__c,IAPL_Owner__c FROM Account WHERE MemberID__c in :nonSurvivingMembers2]){
                cs1.put(objCS.MemberID__c, objCS);
                nonSurvivingAccountIds.add(objCS.Id);
            }
        }
        Map<Id, List<Contact>> nonSurvivingAccountId2ContactsWithPortalUser = mapAccountsToContactsWithPortalUsers(nonSurvivingAccountIds);

        Set<Id> allAccountIdsToCheck = new Set<Id>();
        for(Account m : masters.values()) {
            allAccountIdsToCheck.add(m.Id);
        }
        allAccountIdsToCheck.addAll(nonSurvivingAccountIds);

        Set<Id> accountsWithExpos = new Set<Id>();

        if(!allAccountIdsToCheck.isEmpty()) {
            for(AggregateResult ar : [SELECT Account__c FROM Expo__c WHERE Account__c IN :allAccountIdsToCheck GROUP BY Account__c]) {
                accountsWithExpos.add((Id)ar.get('Account__c'));
            }
        }

        for(Bulk_Merge_Upload__c record: records){
            List<Account> duplicates = new List<Account>();
            try{

                Account master1 = masters1.get(record.Surviving_Member_ID__c);
                Account master = masters.get(record.Surviving_Member_ID__c);
                Account c = cs.get(record.Non_Surviving_Member_ID__c);

                if (c.MYS_Id__c != null) {
                    record.Status__c = 'Fail Merge';
                    record.Fail_Merge_Reason__c = 'Non Surviving Member has MYS Id';
                    continue;
                }
                Boolean masterHasExpo = accountsWithExpos.contains(master.Id);
                Boolean duplicateHasExpo = accountsWithExpos.contains(c.Id);

                if (masterHasExpo && duplicateHasExpo) {
                    record.Status__c = 'Fail Merge';
                    record.Fail_Merge_Reason__c = 'Both Surviving and Non-Surviving Accounts have Expo records';
                    continue;
                }

                if(canMerge(master, c)){
                    duplicates.add(c);
                } else {
                    if(c.IsCustomerPortal == true){
                        handleCustomerPortalAccountMerge(master1, c, record, nonSurvivingAccountId2ContactsWithPortalUser, duplicates);
                    }else {
                        record.Status__c = 'Fail Merge';
                        record.Fail_Merge_Reason__c = 'Non Surviving MemberID Has Enterprise Membership';
                    }
                }
                if(record.Non_Surviving_Member_ID2__c != null ){
                    Account c1 = cs1.get(record.Non_Surviving_Member_ID2__c);
                    Boolean duplicate2HasExpo = accountsWithExpos.contains(c1.Id);
                    if (masterHasExpo && duplicate2HasExpo) {
                        record.Status__c = 'Fail Merge';
                        record.Fail_Merge_Reason__c = 'Both Surviving and Non-Surviving Account (2) have Expo records';
                        continue;
                    }
                    if(canMerge(master, c1)){
                        duplicates.add(c1);
                    } else {
                        if(c1.IsCustomerPortal == true){
                            handleCustomerPortalAccountMerge(master1, c1, record, nonSurvivingAccountId2ContactsWithPortalUser, duplicates);
                        } else {
                            record.Status__c = 'Fail Merge';
                            record.Fail_Merge_Reason__c = 'Non Surviving MemberID Has Enterprise Membership';
                        }
                    }
                }

                if (!duplicates.isEmpty()){
                    if (master1.IAPL_Owner__c == null) {
                        for (Account dup : duplicates) {
                            if (dup.IAPL_Owner__c != null) {
                                master1.IAPL_Owner__c = dup.IAPL_Owner__c;
                                System.debug('Transferring IAPL_Owner__c value from non-surviving record ' + dup.Id + ': ' + dup.IAPL_Owner__c);
                                break; // Take the first available value
                            }
                        }
                    } else {
                        System.debug('Master record already has IAPL_Owner__c value: ' + master1.IAPL_Owner__c);
                    }
                    deleteRedundantAccountContactRelations(master1.Id, duplicates);
                    Database.MergeResult[] results = Database.merge(master1, duplicates, true);

                    for(Database.MergeResult res : results) {
                        if (res.isSuccess()) {
                            List<Id> mergedIds = res.getMergedRecordIds();
                                record.Status__c = 'Complete Merge';
                                record.Fail_Merge_Reason__c = '';
                        } else {
                            record.Status__c = 'Fail Merge';
                            for(Database.Error err : res.getErrors()) {
                                record.Fail_Merge_Reason__c = record.Fail_Merge_Reason__c +':'+err.getMessage();
                            }
                        }
                    }
                }
            }

            catch(Exception e){
                record.Status__c = 'Fail Merge';
                record.Fail_Merge_Reason__c = e.getMessage() ;
            }
        }

        update records;
    }

    private static void deleteRedundantAccountContactRelations(Id masterAccountId, List<Account> mergedRecordList) {
        Set<Id> allAccountIds = new Set<Id>{masterAccountId};
        for (Account obj : mergedRecordList) {
            allAccountIds.add(obj.Id);
        }

        List<AccountContactRelation> allACRs = [
                SELECT Id, ContactId, AccountId, IsDirect
                FROM AccountContactRelation
                WHERE AccountId IN :allAccountIds
        ];

        Set<Id> masterContactIds = new Set<Id>();
        for (AccountContactRelation acr : allACRs) {
            if (acr.AccountId == masterAccountId) {
                masterContactIds.add(acr.ContactId);
            }
        }

        List<AccountContactRelation> acrsToDelete = new List<AccountContactRelation>();
        for (AccountContactRelation acr : allACRs) {
            if (acr.AccountId != masterAccountId && masterContactIds.contains(acr.ContactId) && !acr.IsDirect) {
                acrsToDelete.add(acr);
            }
        }

        if (!acrsToDelete.isEmpty()) {
            System.debug('Deleting ' + acrsToDelete.size() + ' redundant AccountContactRelation records before Account merge');
            delete acrsToDelete;
        }
    }

    public static Map<Id, List<Contact>> mapAccountsToContactsWithPortalUsers(Set<Id> accountIds) {
        Map<Id, List<Contact>> result = new Map<Id, List<Contact>>();
        List<User> portalUsers = new List<User>();
        portalUsers = [SELECT Id, Contact.Id, Contact.AccountId FROM User WHERE Contact.AccountId IN :accountIds];
        if(portalUsers.isEmpty()){
            return result;
        }
        for (User portalUser : portalUsers) {
            if (!result.keySet().contains(portalUser.Contact.AccountId)) {
                result.put(portalUser.Contact.AccountId, new List<Contact>());
            }
            result.get(portalUser.Contact.AccountId).add(portalUser.Contact);
        }
        return result;
    }

    private static void handleCustomerPortalAccountMerge(Account master, Account duplicate, Bulk_Merge_Upload__c record, Map<Id, List<Contact>> nonSurvivingAccountId2ContactsWithPortalUser, List<Account> duplicates) {
        if (nonSurvivingAccountId2ContactsWithPortalUser.keySet().contains(duplicate.Id)) {
            List<Database.SaveResult> accountSaveResult = clearContactLookups(new List<Account>{duplicate});
            if(!accountSaveResult.get(0).isSuccess()){
                record.Status__c = 'Fail Merge';
                record.Fail_Merge_Reason__c = 'Error updating non surviving customer portal Account';
                return;
            }

            List<Database.SaveResult> contactUpdateResults = reparentContacts(nonSurvivingAccountId2ContactsWithPortalUser, master, duplicate);
            for (Database.SaveResult saveResult : contactUpdateResults) {
                if(!saveResult.isSuccess()){
                    record.Status__c = 'Fail Merge';
                    record.Fail_Merge_Reason__c = 'Error when changing Account on one of the contacts';
                    return;
                }
            }
            duplicates.add(duplicate);
        }
    }

    public static List<Database.SaveResult> reparentContacts(Map<Id, List<Contact>> nonSurvivingAccountId2ContactsWithPortalUser, Account master, Account duplicate){
        List<Contact> duplicateContacts = nonSurvivingAccountId2ContactsWithPortalUser.get(duplicate.Id);
        for (Contact c : duplicateContacts) {
            c.AccountId = master.Id;
        }
        return Database.update(duplicateContacts, false);
    }

    public static List<Database.SaveResult> clearContactLookups(List<Account> accounts){
        for (Account acc : accounts) {
            acc.Marketing_Contact__c = null;
            acc.Market_Intelligence_Contact__c = null;
            acc.HR_Contact__c = null;
            acc.Expo_Manager__c = null;
            acc.Exhibitor_Contact__c = null;
            acc.Education_Contact__c = null;
            acc.CEO__c = null;
            acc.Billing_Contact__c = null;
            acc.APEx_Contact__c = null;
            acc.OrderApi__Primary_Contact__c = null;
            acc.DonorApi__Primary_Relationship_Manager__c = null;
            acc.Xchange_Contact__c = null;
        }
        return Database.update(accounts, false);
    }

    public static Boolean canMerge(Account masterRecord, Account nonSurvivingRecord){
        return ((masterRecord.IsCustomerPortal == true && nonSurvivingRecord.Member_Type__c != 'Gold' && nonSurvivingRecord.Member_Type__c != 'Silver' && nonSurvivingRecord.Member_Type__c != 'Bronze') ||
                (masterRecord.IsCustomerPortal == true && masterRecord.Member_Type__c == nonSurvivingRecord.Member_Type__c) ||
                (masterRecord.IsCustomerPortal == false && nonSurvivingRecord.IsCustomerPortal == false && nonSurvivingRecord.Member_Type__c != 'Gold' && nonSurvivingRecord.Member_Type__c != 'Silver' && nonSurvivingRecord.Member_Type__c != 'Bronze')||
                (masterRecord.IsCustomerPortal == false && nonSurvivingRecord.IsCustomerPortal == false && masterRecord.Member_Type__c == nonSurvivingRecord.Member_Type__c));
    }
}