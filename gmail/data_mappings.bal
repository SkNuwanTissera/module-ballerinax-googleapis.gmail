// Copyright (c) 2018, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

import ballerina/lang.array;
import ballerina/lang.'int;
import ballerina/regex;
import ballerina/log;

type mapJson map<json>;

//Includes all the transforming functions which transform required json to type object/record and vice versa

# Transforms JSON message object into Message Type Object.
# + sourceMessageJsonObject - `json` message object
# + return - Returns Message type object
function convertJSONToMessageType(json sourceMessageJsonObject) returns @tainted Message {
    Message targetMessageType = {};

    targetMessageType.id = let var id = sourceMessageJsonObject.id in id is string ? id : EMPTY_STRING;
    targetMessageType.threadId = let var threadId = sourceMessageJsonObject.threadId in threadId is string ? threadId : 
        EMPTY_STRING;
    json|error labelIds = sourceMessageJsonObject.labelIds;
    if (labelIds is json) {
        json[] labelIdsArr = <json[]>labelIds;
        targetMessageType.labelIds = convertJSONArrayToStringArray(labelIdsArr);
    } else {
        targetMessageType.labelIds = [];
    }
    targetMessageType.raw = let var raw = sourceMessageJsonObject.raw in raw is string ? raw : EMPTY_STRING;
    targetMessageType.snippet = let var snippet = sourceMessageJsonObject.snippet in snippet is string ? snippet : 
        EMPTY_STRING;
    targetMessageType.historyId = let var historyId = 
        sourceMessageJsonObject.historyId in historyId is string ? historyId : EMPTY_STRING;
    targetMessageType.internalDate = let var internalDate = 
        sourceMessageJsonObject.internalDate in internalDate is string ? internalDate : EMPTY_STRING;
    json|error sizeEstimate = sourceMessageJsonObject.sizeEstimate;
    if(sizeEstimate is json) {
        targetMessageType.sizeEstimate = sizeEstimate.toString();
    }

    json|error srcMssgHeaders = sourceMessageJsonObject.payload.headers;
    if(srcMssgHeaders is json) {
        targetMessageType.headers = convertJSONToHeaderMap(srcMssgHeaders);
    } else {
        targetMessageType.headers = {};
    }
    targetMessageType.headerDate = getValueForMapKey(targetMessageType.headers, DATE);
    targetMessageType.headerSubject = getValueForMapKey(targetMessageType.headers, SUBJECT);
    targetMessageType.headerTo = getValueForMapKey(targetMessageType.headers, TO);
    targetMessageType.headerFrom = getValueForMapKey(targetMessageType.headers, FROM);
    targetMessageType.headerContentType = getValueForMapKey(targetMessageType.headers, CONTENT_TYPE);
    targetMessageType.headerCc = getValueForMapKey(targetMessageType.headers, CC);
    targetMessageType.headerBcc = getValueForMapKey(targetMessageType.headers, BCC);
    
    targetMessageType.mimeType = let var mimeType = 
        sourceMessageJsonObject.payload.mimeType in mimeType is string ? mimeType : EMPTY_STRING;
    // This is an unused code block
    // string payloadMimeType = sourceMessageJsonObject.payload.mimeType != () ?
    //                                                sourceMessageJsonObject.payload.mimeType.toString() : EMPTY_STRING;

    //Recursively go through the payload and get relevant message body part from content type
    json|error srcMssgJsonPayload = sourceMessageJsonObject.payload;
    if (srcMssgJsonPayload is json){
        targetMessageType.emailBodyInText = getMessageBodyPartFromPayloadByMimeType(srcMssgJsonPayload, TEXT_PLAIN);
        targetMessageType.emailBodyInHTML = getMessageBodyPartFromPayloadByMimeType(srcMssgJsonPayload, TEXT_HTML);
        //Recursively go through the payload and get message attachment and inline image parts
        [MessageBodyPart[], MessageBodyPart[]] parts = getFilePartsFromPayload(srcMssgJsonPayload, [], []);
        MessageBodyPart[] attachments;
        MessageBodyPart[] imageParts;
        [attachments, imageParts] = parts;
        targetMessageType.msgAttachments = attachments;
        targetMessageType.emailInlineImages = imageParts;
    } else {
        targetMessageType.emailBodyInText = {};
        targetMessageType.emailBodyInHTML = {};
        targetMessageType.msgAttachments = [];
        targetMessageType.emailInlineImages = [];
    }

    return targetMessageType;
}

# Transforms MIME Message Part JSON into MessageBody.
# + sourceMessagePartJsonObject - `json` message part object
# + return - Returns MessageBodyPart type
isolated function convertJSONToMsgBodyType(json sourceMessagePartJsonObject) returns MessageBodyPart {
    MessageBodyPart targetMessageBodyType = {};
    if (sourceMessagePartJsonObject != ()){
        targetMessageBodyType.fileId = let var fileId = 
            sourceMessagePartJsonObject.body.attachmentId in fileId is string ? fileId : EMPTY_STRING;
        // body is an object of MessagePartBody in the docs.
        targetMessageBodyType.body = let var body = 
            sourceMessagePartJsonObject.body.data in body is map<json> ? body.toString() : EMPTY_STRING;
        // In the payload body, "size" is an integer.
        targetMessageBodyType.size = let var size = 
            sourceMessagePartJsonObject.body.size in size is int ? size.toString() : EMPTY_STRING;
        targetMessageBodyType.mimeType = let var mimeType = 
            sourceMessagePartJsonObject.mimeType in mimeType is string ? mimeType : EMPTY_STRING;
        targetMessageBodyType.partId = let var partId = 
            sourceMessagePartJsonObject.partId in partId is string ? partId : EMPTY_STRING;
        targetMessageBodyType.fileName = let var fileName = 
            sourceMessagePartJsonObject.filename in fileName is string ? fileName : EMPTY_STRING;

        json|error srcMssgPartHeaders = sourceMessagePartJsonObject.headers;
        if(srcMssgPartHeaders is json) {
            // Headers is an object of type headers
            targetMessageBodyType.bodyHeaders = 
                sourceMessagePartJsonObject.headers !== () ? convertJSONToHeaderMap(srcMssgPartHeaders) : 
                targetMessageBodyType.bodyHeaders;
        } else {
            log:printError("Error occurred while getting headers from src message part.", 'error = srcMssgPartHeaders);
        }
    }
    return targetMessageBodyType;
}

# Transforms single body of MIME Message part into MessageBodyPart Attachment.
# + sourceMessageBodyJsonObject - `json` message body object
# + return - Returns MessageBodyPart type object
isolated function convertJSONToMsgBodyAttachment(json sourceMessageBodyJsonObject) returns MessageBodyPart {
    return {
        fileId: let var fileId = sourceMessageBodyJsonObject.attachmentId in fileId is string ? fileId : EMPTY_STRING,
        body: getFormattedBase64Body(sourceMessageBodyJsonObject),
        size: let var size = sourceMessageBodyJsonObject.size in size is int ? size.toString() : EMPTY_STRING
    };
}

# Format received base64 data string to the valid format.
# + sourceMessageBodyJsonObject - `json` message body object
# + return - Returns attachment body with valid Base64 encoded
isolated function getFormattedBase64Body(json sourceMessageBodyJsonObject)  returns string {
    string formattedBody = let var body = sourceMessageBodyJsonObject.data in body is string ? body : EMPTY_STRING;
    formattedBody = regex:replaceAll(formattedBody, DASH_SYMBOL, PLUS_SYMBOL);
    return regex:replaceAll(formattedBody, UNDERSCORE_SYMBOL, FORWARD_SLASH_SYMBOL);
}

# Transforms mail thread JSON object into MailThread type.
# + sourceThreadJsonObject - `json` message thread object.
# + return - Returns MailThread type
function convertJSONToThreadType(json sourceThreadJsonObject) returns @tainted MailThread {
    return {
        id: let var id = sourceThreadJsonObject.id in id is string ? id : EMPTY_STRING,
        historyId: let var historyId = sourceThreadJsonObject.historyId in historyId is string ? historyId : 
            EMPTY_STRING,
        messages: let var messages = 
            sourceThreadJsonObject.messages in messages is json[] ? convertToMessageArray(messages): []
    };
}

# Converts the JSON message array into Message type array.
# + sourceMessageArrayJsonObject - `json` message array object
# + return - Message type array
function convertToMessageArray(json[] sourceMessageArrayJsonObject) returns @tainted Message[] {
    Message[] messages = [];
    int i = 0;
    foreach json jsonMessage in sourceMessageArrayJsonObject {
        messages[i] = convertJSONToMessageType(jsonMessage);
        i = i + 1;
    }
    return messages;
}

# Transforms user profile JSON object into UserProfile.
# + sourceUserProfileJsonObject - `json` user profile object
# + return - UserProfile type
isolated function convertJSONToUserProfileType(json sourceUserProfileJsonObject) returns UserProfile {
    return {
        emailAddress: let var emailAddress = 
            sourceUserProfileJsonObject.emailAddress in emailAddress is string ? emailAddress : EMPTY_STRING,
        threadsTotal: let var threadsTotal = 
            sourceUserProfileJsonObject.threadsTotal in threadsTotal is int ? threadsTotal.toString() : 
            EMPTY_STRING,
        messagesTotal: let var messagesTotal = 
            sourceUserProfileJsonObject.messagesTotal in messagesTotal is int ? messagesTotal.toString() : 
            EMPTY_STRING,
        historyId: let var historyId = sourceUserProfileJsonObject.historyId in historyId is string ? historyId : 
            EMPTY_STRING
    };
}

# Converts the message part header JSON array to headers.
# + jsonMsgPartHeaders - `json` array of message part headers
# + return - Map of headers
isolated function convertJSONToHeaderMap(json jsonMsgPartHeaders) returns map<string> {
    map<string> headers = {};
    json[] jsonHeaders = <json[]>jsonMsgPartHeaders;
    foreach json jsonHeader in jsonHeaders {
        string headerName = let var name = jsonHeader.name in name is string ? name : EMPTY_STRING;
        headers[headerName] = let var value = jsonHeader.value in value is string ? value : EMPTY_STRING;
    }
    return headers;
}

# Converts the JSON label resource to Label type.
# + sourceLabelJsonObject - `json` label
# + return - Label type object
isolated function convertJSONToLabelType(json sourceLabelJsonObject) returns Label|error {
    Label targetLabel = {};
    map<json>|error srcLabelJsonObjectMap = sourceLabelJsonObject.cloneWithType(mapJson);
    if (srcLabelJsonObjectMap is map<json>) {
        // id
        if (elementExists(srcLabelJsonObjectMap, "id")) {
            targetLabel.id = srcLabelJsonObjectMap["id"].toString();
        } else {
            targetLabel.id = EMPTY_STRING;
        }
        // name
        if (elementExists(srcLabelJsonObjectMap, "name")) {
            targetLabel.name = srcLabelJsonObjectMap["name"].toString();
        } else {
            targetLabel.name = EMPTY_STRING;
        }
        // messageListVisibility
        if (elementExists(srcLabelJsonObjectMap, "messageListVisibility")) {
            targetLabel.messageListVisibility = srcLabelJsonObjectMap["messageListVisibility"].toString();
        } else {
            targetLabel.messageListVisibility = EMPTY_STRING;
        }
        // labelListVisibility
        if (elementExists(srcLabelJsonObjectMap, "labelListVisibility")) {
            targetLabel.labelListVisibility = srcLabelJsonObjectMap["labelListVisibility"].toString();
        } else {
            targetLabel.labelListVisibility = EMPTY_STRING;
        }
        // ownerType
        if (elementExists(srcLabelJsonObjectMap, "ownerType")) {
            targetLabel.ownerType = srcLabelJsonObjectMap["ownerType"].toString();
        } else {
            targetLabel.ownerType = EMPTY_STRING;
        }
        // messgTotal
        if (elementExists(srcLabelJsonObjectMap, "messagesTotal")) {
            int|error messagesTotal = srcLabelJsonObjectMap["messagesTotal"].cloneWithType(int);
            if (messagesTotal is int) {
                targetLabel.messagesTotal = messagesTotal;
            } else {
                error err = error(GMAIL_ERROR_CODE, message = 
                    "Error occurred while converting messagesTotal json to int.");
                return err;
            }
        } else {
            targetLabel.messagesTotal = 0;
        }
        // messagesUnread
        if (elementExists(srcLabelJsonObjectMap, "messagesUnread")) {
            int|error messagesUnread = srcLabelJsonObjectMap["messagesUnread"].cloneWithType(int);
            if (messagesUnread is int) {
                targetLabel.messagesUnread = messagesUnread;
            } else {
                error err = error(GMAIL_ERROR_CODE, 
                    message = "Error occurred while converting messagesUnread json to int.");
                return err;
            }
        } else {
            targetLabel.messagesUnread = 0;
        }
        // threadsUnread
        if (elementExists(srcLabelJsonObjectMap, "threadsUnread")) {
            int|error threadsUnread = srcLabelJsonObjectMap["threadsUnread"].cloneWithType(int);
            if (threadsUnread is int) {
                targetLabel.threadsUnread = threadsUnread;
            } else {
                error err = error(GMAIL_ERROR_CODE, 
                    message = "Error occurred while converting threadsUnread json to int.");
                return err;
            }
        } else {
            targetLabel.threadsUnread = 0;
        }
        // threadsTotal
        if (elementExists(srcLabelJsonObjectMap, "threadsTotal")) {
            int|error threadsTotal = srcLabelJsonObjectMap["threadsTotal"].cloneWithType(int);
            if (threadsTotal is int) {
                targetLabel.threadsTotal = threadsTotal;
            } else {
                error err = error(GMAIL_ERROR_CODE, 
                    message = "Error occurred while converting threadsTotal json to int.");
                return err;
            }
        } else {
            targetLabel.threadsTotal = 0;
        }
        // color
        if (elementExists(srcLabelJsonObjectMap, "color")) {
            json|error color = srcLabelJsonObjectMap["color"];
            if (color is json) {
                map<json>|error colorMap = color.cloneWithType(mapJson);
                if (colorMap is map<json>) {
                    // textColor
                    if (elementExists(colorMap, "textColor")) {
                        targetLabel.textColor = colorMap["textColor"].toString();
                    }
                    // backgroundColor
                    if (elementExists(colorMap, "backgroundColor")) {
                        targetLabel.backgroundColor = colorMap["backgroundColor"].toString();
                    }
                }
            }
        }
        return targetLabel;
    } else {
        log:printError("Error occurred while converting sourceLabelJsonObject json to map of json. sourceLabelJsonObject: " 
            + sourceLabelJsonObject.toString(), 'error = srcLabelJsonObjectMap);
        error err = error(GMAIL_ERROR_CODE, message = 
            "Error occurred while converting sourceLabelJsonObject json to map of json.");
        return err;
    }
}

isolated function convertToInt(json jsonVal) returns int {
    string stringVal = jsonVal.toString();
    if (stringVal != "") {
        int|error intVal = 'int:fromString(stringVal);
        if (intVal is int) {
            return intVal;
        } else {
            error err = error(GMAIL_ERROR_CODE, message = "Error occurred when converting " + stringVal + " to int");
            panic err;
        }
    } else {
        return 0;
    }
}

# Convert JSON label list response to an array of Label type objects.
# + sourceJsonLabelList - Source `json` object
# + return - Returns an array of Label type objects
isolated function convertJSONToLabelTypeList(json sourceJsonLabelList) returns Label[]|error {
    Label[] targetLabelList = [];
    //Convert json object to json array object
    json|error jsonLabelList = sourceJsonLabelList.labels;
    if (jsonLabelList is json) {
        foreach json label in <json[]>jsonLabelList {
            Label|error labelResult = convertJSONToLabelType(label);
            if (labelResult is Label) {
                array:push(targetLabelList, labelResult);
            } else {
                return labelResult;
            }
        }
    } else {
        log:printError("Error occurred while getting label list", 'error = jsonLabelList);
    }
    return targetLabelList;
}

# Converts JSON mailbox history to MailboxHistoryPage Type.
# + sourceJsonMailboxHistory - `json` mailbox history
# + return-  Returns MailboxHistoryPage Type object
function convertJSONToMailboxHistoryPage (json sourceJsonMailboxHistory) returns @tainted MailboxHistoryPage {
    MailboxHistoryPage targetMailboxHistoryPage = {};
    targetMailboxHistoryPage.nextPageToken = let var next = 
        sourceJsonMailboxHistory.nextPageToken in next is string ? next : EMPTY_STRING;
    targetMailboxHistoryPage.historyId = let var historyId = 
        sourceJsonMailboxHistory.historyId in historyId is string ? historyId : EMPTY_STRING;

    if (elementExists(<map<json>>sourceJsonMailboxHistory,"history")) {
        json|error historyList = sourceJsonMailboxHistory.history;
        if (historyList is json) {
            foreach json history in <json[]>historyList {
                array:push(targetMailboxHistoryPage.historyRecords, convertJSONToHistoryType(history));
            }
        } else {
            log:printError("Error occurred while getting history list", 'error = historyList);
        }
    }
    
    return targetMailboxHistoryPage;
}

# Converts JSON list of messages to Message Type list.
# + messages - `json` list of messages
# + targetList - Message Type list to be returned
# + return - Returns Message Type list
function convertJSONToMsgTypeList(json[] messages, @tainted Message[] targetList) returns @tainted Message[] {
    int i = 0;
    foreach json msg in messages {
        targetList[i] = convertJSONToMessageType(msg);
        i = i + 1;
    }
    return targetList;
}

# Converts JSON history to History Type object.
# + sourceJsonHistory - Source `json` History
# + return - Returns History Type object
function convertJSONToHistoryType(json sourceJsonHistory) returns @tainted History {
    History targetHistory = {};
    map<json>|error srcJsonHisMap = sourceJsonHistory.cloneWithType(mapJson);
    if (srcJsonHisMap is map<json>) {
        // id
        if (elementExists(srcJsonHisMap, "id")) {
            targetHistory.id = srcJsonHisMap["id"].toString();
        } else {
            targetHistory.id = EMPTY_STRING;
        }
        // messages
        if (elementExists(srcJsonHisMap, "messages")) {
            targetHistory.messages = 
                convertJSONToMsgTypeList(<json[]>srcJsonHisMap["messages"], targetHistory.messages);
        } else {
            targetHistory.messages = [];
        }
        // messagesAdded
        if (elementExists(srcJsonHisMap, "messagesAdded")) {
            var addedMessages = srcJsonHisMap["messagesAdded"];
            if(addedMessages is json[]) {
                foreach var addedMessage in addedMessages {
                    var historyEvent = addedMessage.cloneWithType(HistoryEvent);
                    if(historyEvent is HistoryEvent) {
                        array:push(targetHistory.messagesAdded,historyEvent);
                    } else {
                        log:printError("Error occured while converting to HistoryEvent type", 'error = historyEvent);
                    }
                }                
            } else {
                log:printError("History change related 'messagesAdded' is not in the format of json[]");
            }
        } else {
            targetHistory.messagesAdded = [];
        }
        // messagesDeleted
        if (elementExists(srcJsonHisMap, "messagesDeleted")) {
            var deletedMessages = srcJsonHisMap["messagesDeleted"];
            if(deletedMessages is json[]) {
                foreach var deletedMessage in deletedMessages {
                    var historyEvent = deletedMessage.cloneWithType(HistoryEvent);
                    if(historyEvent is HistoryEvent) {
                        array:push(targetHistory.messagesDeleted,historyEvent);
                    } else {
                        log:printError("Error occured while converting to HistoryEvent type", 'error = historyEvent);
                    }
                }                
            } else {
                log:printError("History change related 'messagesDeleted' is not in the format of json[]");
            }
        } else {
            targetHistory.messagesDeleted = [];
        }
        // labelsAdded
        if (elementExists(srcJsonHisMap, "labelsAdded")) {
            var addedLabels = srcJsonHisMap["labelsAdded"];
            if(addedLabels is json[]) {
                foreach var addedLabel in addedLabels {
                    var historyEvent = addedLabel.cloneWithType(HistoryEvent);
                    if(historyEvent is HistoryEvent) {
                        array:push(targetHistory.labelsAdded,historyEvent);
                    } else {
                        log:printError("Error occured while converting to HistoryEvent type", 'error = historyEvent);
                    }
                }                
            } else {
                log:printError("History change related 'labelsAdded' is not in the format of json[]");
            }
        } else {
            targetHistory.labelsAdded = [];
        }
        // labelsRemoved
        if (elementExists(srcJsonHisMap, "labelsRemoved")) {
            var removedLabels = srcJsonHisMap["labelsRemoved"];
            if(removedLabels is json[]) {
                foreach var removedLabel in removedLabels {
                    var historyEvent = removedLabel.cloneWithType(HistoryEvent);
                    if(historyEvent is HistoryEvent) {
                        array:push(targetHistory.labelsRemoved,historyEvent);
                    } else {
                        log:printError("Error occured while converting to HistoryEvent type", 'error = historyEvent);
                    }
                }                
            } else {
                log:printError("History change related 'labelsRemoved' is not in the format of json[]");
            }
        } else {
            targetHistory.labelsRemoved = [];
        }
    }
    return targetHistory;
}

# Transform draft JSON object into Draft Type Object.
# + sourceDraftJsonObject - `json` Draft Object
# + return - If successful, returns Draft. Else returns error.
function convertJSONToDraftType(json sourceDraftJsonObject) returns @tainted Draft {
    Draft targetDraft = {};
    targetDraft.id = let var id = sourceDraftJsonObject.id in id is string ? id : EMPTY_STRING;

    json|error message = sourceDraftJsonObject.message;
    if(message is json) {
        targetDraft.message = sourceDraftJsonObject.message !== () ? convertJSONToMessageType(message) : {};
    } else {
        log:printError("Error occurred while getting message from sourceDraftJsonObject.", 'error = message);
    }
    return targetDraft;
}
