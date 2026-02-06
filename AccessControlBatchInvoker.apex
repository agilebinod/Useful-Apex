public with sharing class AccessControlBatchInvoker {

	@InvocableMethod(Label='Access Invoker')
	public static void startBatchJob(List<FlowParams> params) {
		for (FlowParams param : params) {
			BatchableObjectAccessControl batchJob = new BatchableObjectAccessControl(
				param.permissionSetId,
				param.isObjectCreateAccess,
				param.isObjectEditAccess,
				param.isObjectReadAccess,
				param.isObjectViewAllAccess,
				param.isObjectModifyAllAccess,
				param.isFieldEditAccess,
				param.isFieldReadAccess); // test

			Database.executeBatch(batchJob, 2000);
		}
	}

	public class FlowParams {
		@InvocableVariable(Label='Record ID' Required=true)
		public Id permissionSetId;

		@InvocableVariable(Label='Object Create Access' Required=true)
		public Boolean isObjectCreateAccess;

		@InvocableVariable(Label='Object Edit Access' Required=true)
		public Boolean isObjectEditAccess;

		@InvocableVariable(Label='Object Read Access' Required=true)
		public Boolean isObjectReadAccess;

		@InvocableVariable(Label='Object View All Access' Required=true)
		public Boolean isObjectViewAllAccess;

		@InvocableVariable(Label='Object Modify All Access' Required=true)
		public Boolean isObjectModifyAllAccess;

		@InvocableVariable(Label='Field Edit Access' Required=true)
		public Boolean isFieldEditAccess;

		@InvocableVariable(Label='Field Read Access' Required=true)
		public Boolean isFieldReadAccess;
	}
}
