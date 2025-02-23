// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/log;
import ballerina/os;
import ballerina/test;

configurable string testRecipient = os:getEnv("RECIPIENT");
configurable string testSender = os:getEnv("SENDER");
configurable string testCc = os:getEnv("CC");
configurable string testAttachmentPath = os:getEnv("ATTACHMENT_PATH");
configurable string attachmentContentType = os:getEnv("ATTACHMENT_CONTENT_TYPE");
configurable string inlineImagePath = os:getEnv("INLINE_IMAGE_PATH");
configurable string inlineImageName = os:getEnv("INLINE_IMAGE_NAME");
configurable string imageContentType = os:getEnv("IMAGE_CONTENT_TYPE");
configurable string refreshToken = os:getEnv("REFRESH_TOKEN");
configurable string clientId = os:getEnv("CLIENT_ID");
configurable string clientSecret = os:getEnv("CLIENT_SECRET");

ConnectionConfig gmailConfig = {
    auth: {
        refreshUrl: REFRESH_URL,
        refreshToken: refreshToken,
        clientId: clientId,
        clientSecret: clientSecret 
    }
};

Client gmailClient = check new(gmailConfig);


//---------------Do not change the following variables-----------------------//
string testUserId = "me";
//Holds value for message id of text mail sent in testSendTextMessage()
string sentTextMessageId = "";
//Holds value for thread id of text mail sent in testSendTextMessage()
string sentTextMessageThreadId = "";
//Holds value for message id of the html mail sent in testSendHtmlMessage()
string sentHtmlMessageId = "";
//Holds value for attachment id of attachment sent in testSendHTMLMessage()
//Attachment id is set in testReadHTMLMessageWithAttachment()
string readAttachmentFileId = "";
//Holds value for label id of the label created in testCreateLabel()
string createdLabelId = "";
//Holds value for history id of the text message sent in testSendTextMessage()
//History id is set in testReadTextMessage()
string testHistoryId = "";
//Holds value for draft id of the text message created in testCreateDraft()
string createdDraftId = "";

@test:Config {
    groups: ["textMessageTestGroup", "draftTestGroup"]
}
function testSendTextMessage() {
    AttachmentPath[] attachments = [{attachmentPath: testAttachmentPath, mimeType: attachmentContentType}];
    MessageRequest messageRequest = {
        recipient : testRecipient,
        sender : testSender,
        cc : testCc,
        subject : "Text-Email-Subject",
        //---Set Text Body---
        messageBody : "Text Message Body",
        contentType : TEXT_PLAIN,
        //---Set Attachments---
        attachmentPaths : attachments
    };
    log:printInfo("testSendTextMessage");
    //----Send the mail----
    var sendMessageResponse = gmailClient->sendMessage(messageRequest,userId = testUserId);
    if (sendMessageResponse is Message) {
        sentTextMessageId = <@untainted>sendMessageResponse.id;
        sentTextMessageThreadId = <@untainted>sendMessageResponse.threadId;
        test:assertTrue(sentTextMessageId !== "" && sentTextMessageThreadId !== "", msg = "Send Text Message Failed");
    } else {
        test:assertFail(msg = sendMessageResponse.message());
    }
}

@test:Config {
    groups: ["htmlMessageTestGroup"]
}
function testSendHTMLMessage() {
    string htmlBody = "<h1> Email Test HTML Body </h1> <br/> <img src=\"cid:image-" + inlineImageName + "\">";
    MessageRequest messageRequest = {
        recipient : testRecipient,
        sender : testSender,
        cc : testCc,
        subject : "HTML-Email-Subject",
        //---Set HTML Body---    
        messageBody : htmlBody,
        contentType : TEXT_HTML
    };
    //---Set Inline Images---
    InlineImagePath[] inlineImages = [{imagePath: inlineImagePath, mimeType: imageContentType}];
    messageRequest.inlineImagePaths = inlineImages;
    //---Set Attachments---
    AttachmentPath[] attachments = [{attachmentPath: testAttachmentPath, mimeType: attachmentContentType}];
    messageRequest.attachmentPaths = attachments;
    log:printInfo("testSendHTMLMessage");
    //----Send the mail----
    var sendMessageResponse = gmailClient->sendMessage(messageRequest, userId = testUserId);
    string messageId = "";
    string threadId = "";
    if (sendMessageResponse is error) {
        test:assertFail(msg = sendMessageResponse.toString());
    } else {
        messageId = sendMessageResponse.id;
        threadId = sendMessageResponse.threadId;
        sentHtmlMessageId = <@untainted>messageId;
        test:assertTrue(messageId !== "" && threadId !== "", msg = "Send HTML message failed");
    }
}

@test:Config {
    dependsOn: [testSendHTMLMessage],
    groups: ["htmlMessageTestGroup"]
}
function testModifyHTMLMessage() {
    //Modify labels of the message with message id which was sent in testSendHTMLMessage
    log:printInfo("testModifyHTMLMessage");
    var response = gmailClient->modifyMessage(sentHtmlMessageId, ["INBOX"], []);
    if (response is Message) {
        test:assertTrue(response.id == sentHtmlMessageId, msg = "Modify HTML message by adding new label failed");
    } else {
        test:assertFail(msg = response.message());
    }
    response = gmailClient->modifyMessage(sentHtmlMessageId, [], ["INBOX"]);
    if (response is Message) {
        test:assertTrue(response.id == sentHtmlMessageId,
        msg = "Modify HTML message by removing existing label failed");
    } else {
        test:assertFail(msg = response.message());
    }
}

@test:Config {
    
}
function testListMessages() {
    //List All Messages with Label INBOX without including Spam and Trash
    log:printInfo("testListAllMessages");
    MsgSearchFilter searchFilter = {includeSpamTrash: false, labelIds: ["INBOX"]};
    stream<Message,error?>|error msgList = gmailClient->listMessages(filter = searchFilter, userId = testUserId);
    if (msgList is stream<Message,error?>) {
        record {| Message value; |}|error? response = msgList.next();
        test:assertTrue(response is record {| Message value; |}, msg = "Found 0 records");
    } else {
        test:assertFail(msg = msgList.message());
    }
}

@test:Config {
    dependsOn: [testSendDraft],
    groups: ["textMessageTestGroup"]
}
function testReadTextMessage() {
    //Read mail with message id which was sent in testSendSimpleMessage
    log:printInfo("testReadTextMessage");
    var response = gmailClient->readMessage(sentTextMessageId);
    if (response is Message) {
        testHistoryId = response?.historyId is string ? <@untainted>(<string>response?.historyId) : testHistoryId;
        test:assertEquals(response.id, sentTextMessageId, msg = "Read text mail failed");
    } else {
        test:assertFail(msg = response.message());
    }
}

@test:Config {
    dependsOn: [testModifyHTMLMessage],
    groups: ["htmlMessageTestGroup"]
}
function testReadHTMLMessageWithAttachment() {
    //Read mail with message id which sent in testSendWithAttachment
    log:printInfo("testReadMessageWithAttachment");
    var response = gmailClient->readMessage(sentHtmlMessageId);
    if (response is Message) {
        if (response?.msgAttachments is MessageBodyPart[]) {
            MessageBodyPart[] msgAttachments = <MessageBodyPart[]>response?.msgAttachments;
            readAttachmentFileId = msgAttachments[0]?.fileId is string ? <@untainted>(<string>msgAttachments[0]?.fileId)
                                    : readAttachmentFileId;
        }
        test:assertEquals(response.id, sentHtmlMessageId, msg = "Read mail with attachment failed");
    } else {
        test:assertFail(msg = response.message());
    }
}

@test:Config {
    dependsOn: [testReadHTMLMessageWithAttachment],
    groups: ["htmlMessageTestGroup"]
}
function testgetAttachment() {
    log:printInfo("testgetAttachment");
    var response = gmailClient->getAttachment(sentHtmlMessageId, readAttachmentFileId);
    if (response is MessageBodyPart) {
        if (response?.data is string) {
            test:assertTrue(<string>response?.data !==EMPTY_STRING, msg = "Get Attachment failed");
        }
    } else {
        test:assertFail(msg = response.message());        
    }
}

@test:Config {
    dependsOn: [testgetAttachment],
    groups: ["htmlMessageTestGroup"]
}
function testTrashMessage() {
    log:printInfo("testTrashMessage");
    var trash = gmailClient->trashMessage(sentHtmlMessageId);
    if (trash is error) {
        test:assertFail(msg = trash.message());
    } else {
        test:assertTrue(sentHtmlMessageId == trash.id, msg = "Trash mail failed");
    }
}

@test:Config {
    dependsOn: [testTrashMessage],
    groups: ["htmlMessageTestGroup"]
}
function testUntrashMessage() {
    log:printInfo("testUntrashMessage");
    var untrash = gmailClient->untrashMessage(sentHtmlMessageId);
    if (untrash is error) {
        test:assertFail(msg = untrash.message());
    } else {
        test:assertTrue(sentHtmlMessageId == untrash.id, msg = "Trash mail failed");
    }
}

@test:Config {
    dependsOn: [testUntrashMessage],
    groups: ["htmlMessageTestGroup"]
}
function testDeleteMessage() {
    log:printInfo("testDeleteMessage");
    var delete = gmailClient->deleteMessage(sentHtmlMessageId);
    if (delete is error) {
        test:assertFail(msg = delete.toString());
    }
}

@test:Config {

}
function testListThreads() {
    log:printInfo("testListThreads");
    stream<MailThread,error?>|error threadList = gmailClient->listThreads(filter = {includeSpamTrash: false, 
                                                                                   labelIds: ["INBOX"]});
    if (threadList is stream<MailThread,error?>) {
        record {| MailThread value; |}|error? response = threadList.next();
        test:assertTrue(response is record {| MailThread value; |}, msg = "Found 0 records");
    } else {
        test:assertFail(msg = threadList.message());
    }
}

@test:Config {
    dependsOn: [testReadTextMessage],
    groups: ["textMessageTestGroup"]
}
function testReadThread() {
    log:printInfo("testReadThread");
    var thread = gmailClient->readThread(sentTextMessageThreadId, format = FORMAT_METADATA,
        metadataHeaders = ["Subject"]);
    if (thread is MailThread) {
        test:assertEquals(thread.id, sentTextMessageThreadId, msg = "Read thread failed");
    } else {
        test:assertFail(msg = thread.message());
    }
}

@test:Config {
    dependsOn: [testReadThread],
    groups: ["textMessageTestGroup"]
}
function testModifyThread() {
    //Modify labels of the thread with thread id which was sent in testSendTextMessage
    log:printInfo("testModifyThread");
    var response = gmailClient->modifyThread(sentTextMessageThreadId, ["INBOX"], []);
    if (response is MailThread) {
        test:assertTrue(response.id == sentTextMessageThreadId, msg = "Modify thread by adding new label failed");
    } else {
        test:assertFail(msg = response.message());
    }
    response = gmailClient->modifyThread(sentTextMessageThreadId, [], ["INBOX"]);
    if (response is MailThread) {
        test:assertTrue(response.id == sentTextMessageThreadId,
            msg = "Modify thread by removing existing label failed");
    } else {
        test:assertFail(msg = response.message());
    }
}

@test:Config {
    dependsOn: [testModifyThread],
    groups: ["textMessageTestGroup"]
}
function testTrashThread() {
    log:printInfo("testTrashThread");
    var trash = gmailClient->trashThread(sentTextMessageThreadId);
    if (trash is error) {
        test:assertFail(msg = trash.message());
    } else {
        test:assertTrue(sentTextMessageThreadId == trash.id, msg = "Trash thread failed");
    }
}

@test:Config {
    dependsOn: [testTrashThread],
    groups: ["textMessageTestGroup"]
}
function testUnTrashThread() {
    log:printInfo("testUnTrashThread");
    var untrash = gmailClient->untrashThread(sentTextMessageThreadId);
    if (untrash is error) {
        test:assertFail(msg = untrash.message());
    } else {
        test:assertTrue(sentTextMessageThreadId == untrash.id, msg = "Untrash thread failed");
    }
}

@test:Config {
    enable: true,
    dependsOn: [testUnTrashThread],
    groups: ["textMessageTestGroup"]
}
function testDeleteThread() {
    log:printInfo("testDeleteThread");
    var delete = gmailClient->deleteThread(sentTextMessageThreadId);
    if (delete is error) {
        test:assertFail(msg = delete.toString());
    }
}

@test:Config {
    groups: ["userTestGroup"]
}
function testgetUserProfile() {
    log:printInfo("testgetUserProfile");
    var profile = gmailClient->getUserProfile(testUserId);
    if (profile is UserProfile) {
        test:assertTrue(profile.emailAddress != EMPTY_STRING, msg = "Get User Profile failed");
    } else {
        test:assertFail(msg = profile.message());
    }
}

@test:Config {
    dependsOn: [testUpdateLabel],
    groups: ["labelTestGroup"]
}
function testGetLabel() {
    log:printInfo("testgetLabel");
    var response = gmailClient->getLabel(createdLabelId);
    if (response is Label) {
        test:assertTrue(response.id !== EMPTY_STRING, msg = "Get Label failed");
    } else {
        test:assertFail(msg = response.message());
    }
}

@test:Config {
    groups: ["labelTestGroup"]
}
function testCreateLabel() {
    log:printInfo("testCreateLabel");
    var createLabelResponse = gmailClient->createLabel("Test", "labelShow", "show");
    if (createLabelResponse is Label) {
        createdLabelId = <@untainted>createLabelResponse.id;
        test:assertTrue(createdLabelId != "null", msg = "Create Label failed");
    } else {
        test:assertFail(msg = createLabelResponse.message());
    }
}

@test:Config {
    groups: ["labelTestGroup"]
}
function testListLabels() {
    log:printInfo("testListLabels");
    var listLabelResponse = gmailClient->listLabels(testUserId);
    if (listLabelResponse is error) {
        test:assertFail(msg = listLabelResponse.message());
    }
}

@test:Config {
    dependsOn: [testGetLabel],
    groups: ["labelTestGroup"]
}
function testDeleteLabel() {
    log:printInfo("testDeleteLabel");
    var deleteLabelResponse = gmailClient->deleteLabel(createdLabelId);
    if (deleteLabelResponse is error) {
        test:assertFail(msg = deleteLabelResponse.toString());
    }
}

@test:Config {
    dependsOn: [testCreateLabel],
    groups: ["labelTestGroup"]
}
function testUpdateLabel() {
    log:printInfo("testUpdateLabel");
    string updateName = "updateTest";
    string updateBgColor = "#16a766";
    string updateTxtColor = "#000000";
    var updateLabelResponse = gmailClient->updateLabel(createdLabelId, name = updateName,
    backgroundColor = updateBgColor, textColor = updateTxtColor);
    if (updateLabelResponse is error) {
        test:assertFail(msg = updateLabelResponse.message());
    } else {
        test:assertTrue(updateLabelResponse.name == updateName &&
        updateLabelResponse?.color?.backgroundColor == updateBgColor &&
        updateLabelResponse?.color?.textColor == updateTxtColor, msg = "Update Label failed");
    }
}

@test:Config {
    dependsOn: [testReadTextMessage],
    groups: ["textMessageTestGroup"]
}
function testListHistory() {
    log:printInfo("testListTheHistory");
    string[] historyTypes = ["labelAdded", "labelRemoved", "messageAdded", "messageDeleted"];
    stream<History,error?>|error listHistoryResponse = gmailClient->listHistory(testHistoryId, 
                                                                               historyTypes = historyTypes);
    if (listHistoryResponse is stream<History,error?>) {
        record {| History value; |}|error? response = listHistoryResponse.next();
        test:assertTrue(response is record {| History value; |}, msg = "Found 0 records");
    } else {
        test:assertFail(msg = listHistoryResponse.message());
    }
}

@test:Config {
    dependsOn: [testCreateDraft],
    groups: ["draftTestGroup"]
}
function testListDrafts() {
    //List maximum of ten results for Drafts without including Spam and Trash
    log:printInfo("testListDrafts");
    DraftSearchFilter searchFilter = {includeSpamTrash: false, maxResults: 10};
    stream<Draft,error?>|error msgList = gmailClient->listDrafts(filter = searchFilter);
    if (msgList is stream<Draft,error?>) {
        record {| Draft value; |}|error? response = msgList.next();
        test:assertTrue(response is record {| Draft value; |}, msg = "Found 0 records");
    } else {
        test:assertFail(msg = msgList.message());
    }
}

@test:Config {
    dependsOn: [testSendTextMessage],
    groups: ["draftTestGroup"]
}
function testCreateDraft() {
    log:printInfo("testCreateDraft");
    string messageBody = "Draft Text Message Body";
    MessageRequest messageRequest = {
        recipient : testRecipient,
        subject : "Create Draft Subject",
        sender : testSender,
        cc : testCc,
        messageBody : messageBody,
        contentType : TEXT_PLAIN
    };
    var draftResponse = gmailClient->createDraft(messageRequest, threadId = sentTextMessageThreadId);
    if (draftResponse is string) {
        test:assertTrue(draftResponse != "null", msg = "Create Draft failed");
        createdDraftId = <@untainted>draftResponse;
    } else {
        test:assertFail(msg = draftResponse.message());
    }
}

@test:Config {
    dependsOn: [testListDrafts],
    groups: ["draftTestGroup"]
}
function testUpdateDraft() {
    log:printInfo("testUpdateDraft");
    string messageBody = "Updated Draft Text Message Body";
    MessageRequest messageRequest = {
        recipient : testRecipient,
        sender : testSender,
        messageBody : messageBody,
        subject : "Update Draft Subject",
        contentType : TEXT_PLAIN
    };    
    AttachmentPath[] attachments = [{attachmentPath: testAttachmentPath, mimeType: attachmentContentType}];
    messageRequest.attachmentPaths = attachments;
    var draftResponse = gmailClient->updateDraft(createdDraftId, messageRequest);
    if (draftResponse is string) {
        test:assertTrue(draftResponse == createdDraftId, msg = "Update Draft failed");
    } else {
        test:assertFail(msg = draftResponse.message());
    }
}

@test:Config {
    dependsOn: [testUpdateDraft],
    groups: ["draftTestGroup"]
}
function testReadDraft() {
    log:printInfo("testReadDraft");
    var draftResponse = gmailClient->readDraft(createdDraftId);
    if (draftResponse is Draft) {
        test:assertTrue(draftResponse.id == createdDraftId, msg = "Read Draft failed");
    } else {
        test:assertFail(msg = draftResponse.message());
    }
}

@test:Config {
    dependsOn: [testReadDraft],
    groups: ["draftTestGroup"]
}
function testSendDraft() {
    log:printInfo("testSendDraft");
    var sendDraftResponse = gmailClient->sendDraft(createdDraftId);
    if (sendDraftResponse is error) {
        test:assertFail(msg = sendDraftResponse.message());
    } else {
        test:assertTrue(sendDraftResponse.id !== "" && sendDraftResponse.threadId !== "",
                        msg = "Send HTML message failed");
    }
}

@test:Config {
    groups: ["draftTestGroup"]
}
function testDeleteDraft() {
    log:printInfo("testDeleteDraft");
    //Create a new draft first
    MessageRequest messageRequest = {
        recipient : testRecipient,
        sender : testSender,
        subject : "Draft To Delete",
        messageBody : "Draft Text Message Body To Delete",
        contentType : TEXT_PLAIN
    };    
    var draftResponse = gmailClient->createDraft(messageRequest);
    string draftIdToDelete = "";
    if (draftResponse is string) {
        test:assertTrue(draftResponse != "null", msg = "Create Draft failed");
        draftIdToDelete = <@untainted>draftResponse;
    } else {
        test:assertFail(msg = draftResponse.message());
    }
    //Delete the created draft
    var deleteResponse = gmailClient->deleteDraft(draftIdToDelete);
    if (deleteResponse is error) {
        test:assertFail(msg = deleteResponse.toString());
    }
}
