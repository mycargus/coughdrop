import $ from 'jquery';
import stashes from './_stashes';
import tts_voices from './tts_voices';
import dbman from './dbman';

// ;/*! IndexedDBShim - v0.1.2 - 2014-10-21 */
// "use strict";var idbModules={},cleanInterface=!1;(function(){var e={test:!0};if(Object.defineProperty)try{Object.defineProperty(e,"test",{enumerable:!1}),e.test&&(cleanInterface=!0)}catch(t){}})(),function(e){function t(e,t,n,o){n.target=t,"function"==typeof t[e]&&t[e].apply(t,[n]),"function"==typeof o&&o()}function n(t,n,o){var r;try{r=new DOMException.prototype.constructor(0,n)}catch(i){r=Error(n)}throw r.name=t,r.message=n,e.DEBUG&&(console.log(t,n,o,r),console.trace&&console.trace()),r}var o=function(){this.length=0,this._items=[],cleanInterface&&Object.defineProperty(this,"_items",{enumerable:!1})};if(o.prototype={contains:function(e){return-1!==this._items.indexOf(e)},item:function(e){return this._items[e]},indexOf:function(e){return this._items.indexOf(e)},push:function(e){this._items.push(e),this.length+=1;for(var t=0;this._items.length>t;t++)this[t]=this._items[t]},splice:function(){this._items.splice.apply(this._items,arguments),this.length=this._items.length;for(var e in this)e===parseInt(e,10)+""&&delete this[e];for(e=0;this._items.length>e;e++)this[e]=this._items[e]}},cleanInterface)for(var r in{indexOf:!1,push:!1,splice:!1})Object.defineProperty(o.prototype,r,{enumerable:!1});e.util={throwDOMException:n,callback:t,quote:function(e){return"'"+e+"'"},StringList:o}}(idbModules),function(idbModules){var Sca=function(){return{decycle:function(object,callback){function checkForCompletion(){0===queuedObjects.length&&returnCallback(derezObj)}function readBlobAsDataURL(e,t){var n=new FileReader;n.onloadend=function(e){var n=e.target.result,o="blob";updateEncodedBlob(n,t,o)},n.readAsDataURL(e)}function updateEncodedBlob(dataURL,path,blobtype){var encoded=queuedObjects.indexOf(path);path=path.replace("$","derezObj"),eval(path+'.$enc="'+dataURL+'"'),eval(path+'.$type="'+blobtype+'"'),queuedObjects.splice(encoded,1),checkForCompletion()}function derez(e,t){var n,o,r;if(!("object"!=typeof e||null===e||e instanceof Boolean||e instanceof Date||e instanceof Number||e instanceof RegExp||e instanceof Blob||e instanceof String)){for(n=0;objects.length>n;n+=1)if(objects[n]===e)return{$ref:paths[n]};if(objects.push(e),paths.push(t),"[object Array]"===Object.prototype.toString.apply(e))for(r=[],n=0;e.length>n;n+=1)r[n]=derez(e[n],t+"["+n+"]");else{r={};for(o in e)Object.prototype.hasOwnProperty.call(e,o)&&(r[o]=derez(e[o],t+"["+JSON.stringify(o)+"]"))}return r}return e instanceof Blob?(queuedObjects.push(t),readBlobAsDataURL(e,t)):e instanceof Boolean?e={$type:"bool",$enc:""+e}:e instanceof Date?e={$type:"date",$enc:e.getTime()}:e instanceof Number?e={$type:"num",$enc:""+e}:e instanceof RegExp&&(e={$type:"regex",$enc:""+e}),e}var objects=[],paths=[],queuedObjects=[],returnCallback=callback,derezObj=derez(object,"$");checkForCompletion()},retrocycle:function retrocycle($){function dataURLToBlob(e){var t,n,o,r=";base64,";if(-1===e.indexOf(r))return n=e.split(","),t=n[0].split(":")[1],o=n[1],new Blob([o],{type:t});n=e.split(r),t=n[0].split(":")[1],o=window.atob(n[1]);for(var i=o.length,a=new Uint8Array(i),s=0;i>s;++s)a[s]=o.charCodeAt(s);return new Blob([a.buffer],{type:t})}function rez(value){var i,item,name,path;if(value&&"object"==typeof value)if("[object Array]"===Object.prototype.toString.apply(value))for(i=0;value.length>i;i+=1)item=value[i],item&&"object"==typeof item&&(path=item.$ref,value[i]="string"==typeof path&&px.test(path)?eval(path):rez(item));else if(void 0!==value.$type)switch(value.$type){case"blob":case"file":value=dataURLToBlob(value.$enc);break;case"bool":value=Boolean("true"===value.$enc);break;case"date":value=new Date(value.$enc);break;case"num":value=Number(value.$enc);break;case"regex":value=eval(value.$enc)}else for(name in value)"object"==typeof value[name]&&(item=value[name],item&&(path=item.$ref,value[name]="string"==typeof path&&px.test(path)?eval(path):rez(item)));return value}var px=/^\$(?:\[(?:\d+|\"(?:[^\\\"\u0000-\u001f]|\\([\\\"\/bfnrt]|u[0-9a-zA-Z]{4}))*\")\])*$/;return rez($),$},encode:function(e,t){function n(e){t(JSON.stringify(e))}this.decycle(e,n)},decode:function(e){return this.retrocycle(JSON.parse(e))}}}();idbModules.Sca=Sca}(idbModules),function(e){var t=["","number","string","boolean","object","undefined"],n=function(){return{encode:function(e){return t.indexOf(typeof e)+"-"+JSON.stringify(e)},decode:function(e){return e===void 0?void 0:JSON.parse(e.substring(2))}}},o={number:n("number"),"boolean":n(),object:n(),string:{encode:function(e){return t.indexOf("string")+"-"+e},decode:function(e){return""+e.substring(2)}},undefined:{encode:function(){return t.indexOf("undefined")+"-undefined"},decode:function(){return void 0}}},r=function(){return{encode:function(e){return o[typeof e].encode(e)},decode:function(e){return o[t[e.substring(0,1)]].decode(e)}}}();e.Key=r}(idbModules),function(e){var t=function(e,t){return{type:e,debug:t,bubbles:!1,cancelable:!1,eventPhase:0,timeStamp:new Date}};e.Event=t}(idbModules),function(e){var t=function(){this.onsuccess=this.onerror=this.result=this.error=this.source=this.transaction=null,this.readyState="pending"},n=function(){this.onblocked=this.onupgradeneeded=null};n.prototype=t,e.IDBRequest=t,e.IDBOpenRequest=n}(idbModules),function(e,t){var n=function(e,t,n,o){this.lower=e,this.upper=t,this.lowerOpen=n,this.upperOpen=o};n.only=function(e){return new n(e,e,!1,!1)},n.lowerBound=function(e,o){return new n(e,t,o,t)},n.upperBound=function(e){return new n(t,e,t,open)},n.bound=function(e,t,o,r){return new n(e,t,o,r)},e.IDBKeyRange=n}(idbModules),function(e,t){function n(n,o,r,i,a,s){!n||n instanceof e.IDBKeyRange||(n=new e.IDBKeyRange(n,n,!1,!1)),this.__range=n,this.source=this.__idbObjectStore=r,this.__req=i,this.key=t,this.direction=o,this.__keyColumnName=a,this.__valueColumnName=s,this.__valueDecoder="value"===s?e.Sca:e.Key,this.source.transaction.__active||e.util.throwDOMException("TransactionInactiveError - The transaction this IDBObjectStore belongs to is not active."),this.__offset=-1,this.__lastKeyContinued=t,this["continue"]()}n.prototype.__find=function(n,o,r,i,a){a=a||1;var s=this,c=["SELECT * FROM ",e.util.quote(s.__idbObjectStore.name)],u=[];c.push("WHERE ",s.__keyColumnName," NOT NULL"),!s.__range||s.__range.lower===t&&s.__range.upper===t||(c.push("AND"),s.__range.lower!==t&&(c.push(s.__keyColumnName+(s.__range.lowerOpen?" >":" >= ")+" ?"),u.push(e.Key.encode(s.__range.lower))),s.__range.lower!==t&&s.__range.upper!==t&&c.push("AND"),s.__range.upper!==t&&(c.push(s.__keyColumnName+(s.__range.upperOpen?" < ":" <= ")+" ?"),u.push(e.Key.encode(s.__range.upper)))),n!==t&&(s.__lastKeyContinued=n,s.__offset=0),s.__lastKeyContinued!==t&&(c.push("AND "+s.__keyColumnName+" >= ?"),u.push(e.Key.encode(s.__lastKeyContinued)));var d="prev"===s.direction||"prevunique"===s.direction?"DESC":"ASC";c.push("ORDER BY ",s.__keyColumnName," "+d),c.push("LIMIT "+a+" OFFSET "+s.__offset),e.DEBUG&&console.log(c.join(" "),u),s.__prefetchedData=null,o.executeSql(c.join(" "),u,function(n,o){o.rows.length>1?(s.__prefetchedData=o.rows,s.__prefetchedIndex=0,e.DEBUG&&console.log("Preloaded "+s.__prefetchedData.length+" records for cursor"),s.__decode(o.rows.item(0),r)):1===o.rows.length?s.__decode(o.rows.item(0),r):(e.DEBUG&&console.log("Reached end of cursors"),r(t,t))},function(t,n){e.DEBUG&&console.log("Could not execute Cursor.continue"),i(n)})},n.prototype.__decode=function(t,n){var o=e.Key.decode(t[this.__keyColumnName]),r=this.__valueDecoder.decode(t[this.__valueColumnName]),i=e.Key.decode(t.key);n(o,r,i)},n.prototype["continue"]=function(n){var o=e.cursorPreloadPackSize||100,r=this;this.__idbObjectStore.transaction.__addToTransactionQueue(function(e,i,a,s){r.__offset++;var c=function(e,n,o){r.key=e,r.value=n,r.primaryKey=o,a(r.key!==t?r:t,r.__req)};return r.__prefetchedData&&(r.__prefetchedIndex++,r.__prefetchedIndex<r.__prefetchedData.length)?(r.__decode(r.__prefetchedData.item(r.__prefetchedIndex),c),t):(r.__find(n,e,c,s,o),t)})},n.prototype.advance=function(n){0>=n&&e.util.throwDOMException("Type Error - Count is invalid - 0 or negative",n);var o=this;this.__idbObjectStore.transaction.__addToTransactionQueue(function(e,r,i,a){o.__offset+=n,o.__find(t,e,function(e,n){o.key=e,o.value=n,i(o.key!==t?o:t,o.__req)},a)})},n.prototype.update=function(n){var o=this,r=this.__idbObjectStore.transaction.__createRequest(function(){});return e.Sca.encode(n,function(i){o.__idbObjectStore.transaction.__pushToQueue(r,function(r,a,s,c){o.__find(t,r,function(t,a,u){var d=o.__idbObjectStore,l=o.__idbObjectStore.transaction.db.__storeProperties,_=[i],f="UPDATE "+e.util.quote(d.name)+" SET value = ?",p=l[d.name]&&l[d.name].indexList;if(p)for(var h in p){var b=p[h];f+=", "+h+" = ?",_.push(e.Key.encode(n[b.keyPath]))}f+=" WHERE key = ?",_.push(e.Key.encode(u)),e.DEBUG&&console.log(f,i,t,u),r.executeSql(f,_,function(e,n){o.__prefetchedData=null,1===n.rowsAffected?s(t):c("No rows with key found"+t)},function(e,t){c(t)})},c)})}),r},n.prototype["delete"]=function(){var n=this;return this.__idbObjectStore.transaction.__addToTransactionQueue(function(o,r,i,a){n.__find(t,o,function(r,s,c){var u="DELETE FROM  "+e.util.quote(n.__idbObjectStore.name)+" WHERE key = ?";e.DEBUG&&console.log(u,r,c),o.executeSql(u,[e.Key.encode(c)],function(e,o){n.__prefetchedData=null,1===o.rowsAffected?(n.__offset--,i(t)):a("No rows with key found"+r)},function(e,t){a(t)})},a)})},e.IDBCursor=n}(idbModules),function(idbModules,undefined){function IDBIndex(e,t){this.indexName=this.name=e,this.__idbObjectStore=this.objectStore=this.source=t;var n=t.transaction.db.__storeProperties[t.name],o=n&&n.indexList;this.keyPath=o&&o[e]&&o[e].keyPath||e,["multiEntry","unique"].forEach(function(t){this[t]=!!(o&&o[e]&&o[e].optionalParams&&o[e].optionalParams[t])},this)}IDBIndex.prototype.__createIndex=function(indexName,keyPath,optionalParameters){var me=this,transaction=me.__idbObjectStore.transaction;transaction.__addToTransactionQueue(function(tx,args,success,failure){me.__idbObjectStore.__getStoreProps(tx,function(){function error(){idbModules.util.throwDOMException(0,"Could not create new index",arguments)}2!==transaction.mode&&idbModules.util.throwDOMException(0,"Invalid State error, not a version transaction",me.transaction);var idxList=JSON.parse(me.__idbObjectStore.__storeProps.indexList);idxList[indexName]!==undefined&&idbModules.util.throwDOMException(0,"Index already exists on store",idxList);var columnName=indexName;idxList[indexName]={columnName:columnName,keyPath:keyPath,optionalParams:optionalParameters},me.__idbObjectStore.__storeProps.indexList=JSON.stringify(idxList);var sql=["ALTER TABLE",idbModules.util.quote(me.__idbObjectStore.name),"ADD",columnName,"BLOB"].join(" ");idbModules.DEBUG&&console.log(sql),tx.executeSql(sql,[],function(tx,data){tx.executeSql("SELECT * FROM "+idbModules.util.quote(me.__idbObjectStore.name),[],function(tx,data){(function initIndexForRow(i){if(data.rows.length>i)try{var value=idbModules.Sca.decode(data.rows.item(i).value),indexKey=eval("value['"+keyPath+"']");tx.executeSql("UPDATE "+idbModules.util.quote(me.__idbObjectStore.name)+" set "+columnName+" = ? where key = ?",[idbModules.Key.encode(indexKey),data.rows.item(i).key],function(){initIndexForRow(i+1)},error)}catch(e){initIndexForRow(i+1)}else idbModules.DEBUG&&console.log("Updating the indexes in table",me.__idbObjectStore.__storeProps),tx.executeSql("UPDATE __sys__ set indexList = ? where name = ?",[me.__idbObjectStore.__storeProps.indexList,me.__idbObjectStore.name],function(){me.__idbObjectStore.__setReadyState("createIndex",!0),success(me)},error)})(0)},error)},error)},"createObjectStore")})},IDBIndex.prototype.openCursor=function(e,t){var n=new idbModules.IDBRequest;return new idbModules.IDBCursor(e,t,this.source,n,this.indexName,"value"),n},IDBIndex.prototype.openKeyCursor=function(e,t){var n=new idbModules.IDBRequest;return new idbModules.IDBCursor(e,t,this.source,n,this.indexName,"key"),n},IDBIndex.prototype.__fetchIndexData=function(e,t){var n=this;return n.__idbObjectStore.transaction.__addToTransactionQueue(function(o,r,i,a){var s=["SELECT * FROM ",idbModules.util.quote(n.__idbObjectStore.name)," WHERE",n.indexName,"NOT NULL"],c=[];e!==undefined&&(s.push("AND",n.indexName," = ?"),c.push(idbModules.Key.encode(e))),idbModules.DEBUG&&console.log("Trying to fetch data for Index",s.join(" "),c),o.executeSql(s.join(" "),c,function(e,n){var o;o="count"===t?n.rows.length:0===n.rows.length?undefined:"key"===t?idbModules.Key.decode(n.rows.item(0).key):idbModules.Sca.decode(n.rows.item(0).value),i(o)},a)})},IDBIndex.prototype.get=function(e){return this.__fetchIndexData(e,"value")},IDBIndex.prototype.getKey=function(e){return this.__fetchIndexData(e,"key")},IDBIndex.prototype.count=function(e){return this.__fetchIndexData(e,"count")},idbModules.IDBIndex=IDBIndex}(idbModules),function(idbModules){var IDBObjectStore=function(e,t,n){this.name=e,this.transaction=t,this.__ready={},this.__setReadyState("createObjectStore",n===void 0?!0:n),this.indexNames=new idbModules.util.StringList;var o=t.db.__storeProperties;if(o[e]&&o[e].indexList){var r=o[e].indexList;for(var i in r)r.hasOwnProperty(i)&&this.indexNames.push(i)}};IDBObjectStore.prototype.__setReadyState=function(e,t){this.__ready[e]=t},IDBObjectStore.prototype.__waitForReady=function(e,t){var n=!0;if(t!==void 0)n=this.__ready[t]===void 0?!0:this.__ready[t];else for(var o in this.__ready)this.__ready[o]||(n=!1);if(n)e();else{idbModules.DEBUG&&console.log("Waiting for to be ready",t);var r=this;window.setTimeout(function(){r.__waitForReady(e,t)},100)}},IDBObjectStore.prototype.__getStoreProps=function(e,t,n){var o=this;this.__waitForReady(function(){o.__storeProps?(idbModules.DEBUG&&console.log("Store properties - cached",o.__storeProps),t(o.__storeProps)):e.executeSql("SELECT * FROM __sys__ where name = ?",[o.name],function(e,n){1!==n.rows.length?t():(o.__storeProps={name:n.rows.item(0).name,indexList:n.rows.item(0).indexList,autoInc:n.rows.item(0).autoInc,keyPath:n.rows.item(0).keyPath},idbModules.DEBUG&&console.log("Store properties",o.__storeProps),t(o.__storeProps))},function(){t()})},n)},IDBObjectStore.prototype.__deriveKey=function(tx,value,key,callback){function getNextAutoIncKey(){tx.executeSql("SELECT * FROM sqlite_sequence where name like ?",[me.name],function(e,t){1!==t.rows.length?callback(0):callback(t.rows.item(0).seq)},function(e,t){idbModules.util.throwDOMException(0,"Data Error - Could not get the auto increment value for key",t)})}var me=this;me.__getStoreProps(tx,function(props){if(props||idbModules.util.throwDOMException(0,"Data Error - Could not locate defination for this table",props),props.keyPath)if(key!==void 0&&idbModules.util.throwDOMException(0,"Data Error - The object store uses in-line keys and the key parameter was provided",props),value)try{var primaryKey=eval("value['"+props.keyPath+"']");void 0===primaryKey?"true"===props.autoInc?getNextAutoIncKey():idbModules.util.throwDOMException(0,"Data Error - Could not eval key from keyPath"):callback(primaryKey)}catch(e){idbModules.util.throwDOMException(0,"Data Error - Could not eval key from keyPath",e)}else idbModules.util.throwDOMException(0,"Data Error - KeyPath was specified, but value was not");else key!==void 0?callback(key):"false"===props.autoInc?idbModules.util.throwDOMException(0,"Data Error - The object store uses out-of-line keys and has no key generator and the key parameter was not provided. ",props):getNextAutoIncKey()})},IDBObjectStore.prototype.__insertData=function(tx,encoded,value,primaryKey,success,error){var paramMap={};primaryKey!==void 0&&(paramMap.key=idbModules.Key.encode(primaryKey));var indexes=JSON.parse(this.__storeProps.indexList);for(var key in indexes)try{paramMap[indexes[key].columnName]=idbModules.Key.encode(eval("value['"+indexes[key].keyPath+"']"))}catch(e){error(e)}var sqlStart=["INSERT INTO ",idbModules.util.quote(this.name),"("],sqlEnd=[" VALUES ("],sqlValues=[];for(key in paramMap)sqlStart.push(key+","),sqlEnd.push("?,"),sqlValues.push(paramMap[key]);sqlStart.push("value )"),sqlEnd.push("?)"),sqlValues.push(encoded);var sql=sqlStart.join(" ")+sqlEnd.join(" ");idbModules.DEBUG&&console.log("SQL for adding",sql,sqlValues),tx.executeSql(sql,sqlValues,function(){success(primaryKey)},function(e,t){error(t)})},IDBObjectStore.prototype.add=function(e,t){var n=this,o=n.transaction.__createRequest(function(){});return idbModules.Sca.encode(e,function(r){n.transaction.__pushToQueue(o,function(o,i,a,s){n.__deriveKey(o,e,t,function(t){n.__insertData(o,r,e,t,a,s)})})}),o},IDBObjectStore.prototype.put=function(e,t){var n=this,o=n.transaction.__createRequest(function(){});return idbModules.Sca.encode(e,function(r){n.transaction.__pushToQueue(o,function(o,i,a,s){n.__deriveKey(o,e,t,function(t){var i="DELETE FROM "+idbModules.util.quote(n.name)+" where key = ?";o.executeSql(i,[idbModules.Key.encode(t)],function(o,i){idbModules.DEBUG&&console.log("Did the row with the",t,"exist? ",i.rowsAffected),n.__insertData(o,r,e,t,a,s)},function(e,t){s(t)})})})}),o},IDBObjectStore.prototype.get=function(e){var t=this;return t.transaction.__addToTransactionQueue(function(n,o,r,i){t.__waitForReady(function(){var o=idbModules.Key.encode(e);idbModules.DEBUG&&console.log("Fetching",t.name,o),n.executeSql("SELECT * FROM "+idbModules.util.quote(t.name)+" where key = ?",[o],function(e,t){idbModules.DEBUG&&console.log("Fetched data",t);try{if(0===t.rows.length)return r();r(idbModules.Sca.decode(t.rows.item(0).value))}catch(n){idbModules.DEBUG&&console.log(n),r(void 0)}},function(e,t){i(t)})})})},IDBObjectStore.prototype["delete"]=function(e){var t=this;return t.transaction.__addToTransactionQueue(function(n,o,r,i){t.__waitForReady(function(){var o=idbModules.Key.encode(e);idbModules.DEBUG&&console.log("Fetching",t.name,o),n.executeSql("DELETE FROM "+idbModules.util.quote(t.name)+" where key = ?",[o],function(e,t){idbModules.DEBUG&&console.log("Deleted from database",t.rowsAffected),r()},function(e,t){i(t)})})})},IDBObjectStore.prototype.clear=function(){var e=this;return e.transaction.__addToTransactionQueue(function(t,n,o,r){e.__waitForReady(function(){t.executeSql("DELETE FROM "+idbModules.util.quote(e.name),[],function(e,t){idbModules.DEBUG&&console.log("Cleared all records from database",t.rowsAffected),o()},function(e,t){r(t)})})})},IDBObjectStore.prototype.count=function(e){var t=this;return t.transaction.__addToTransactionQueue(function(n,o,r,i){t.__waitForReady(function(){var o="SELECT * FROM "+idbModules.util.quote(t.name)+(e!==void 0?" WHERE key = ?":""),a=[];e!==void 0&&a.push(idbModules.Key.encode(e)),n.executeSql(o,a,function(e,t){r(t.rows.length)},function(e,t){i(t)})})})},IDBObjectStore.prototype.openCursor=function(e,t){var n=new idbModules.IDBRequest;return new idbModules.IDBCursor(e,t,this,n,"key","value"),n},IDBObjectStore.prototype.index=function(e){var t=new idbModules.IDBIndex(e,this);return t},IDBObjectStore.prototype.createIndex=function(e,t,n){var o=this;n=n||{},o.__setReadyState("createIndex",!1);var r=new idbModules.IDBIndex(e,o);o.__waitForReady(function(){r.__createIndex(e,t,n)},"createObjectStore"),o.indexNames.push(e);var i=o.transaction.db.__storeProperties[o.name];return i.indexList[e]={keyPath:t,optionalParams:n},r},IDBObjectStore.prototype.deleteIndex=function(e){var t=new idbModules.IDBIndex(e,this,!1);return t.__deleteIndex(e),t},idbModules.IDBObjectStore=IDBObjectStore}(idbModules),function(e){var t=0,n=1,o=2,r=function(o,r,i){if("number"==typeof r)this.mode=r,2!==r&&e.DEBUG&&console.log("Mode should be a string, but was specified as ",r);else if("string"==typeof r)switch(r){case"readwrite":this.mode=n;break;case"readonly":this.mode=t;break;default:this.mode=t}this.storeNames="string"==typeof o?[o]:o;for(var a=0;this.storeNames.length>a;a++)i.objectStoreNames.contains(this.storeNames[a])||e.util.throwDOMException(0,"The operation failed because the requested database object could not be found. For example, an object store did not exist but was being opened.",this.storeNames[a]);this.__active=!0,this.__running=!1,this.__requests=[],this.__aborted=!1,this.db=i,this.error=null,this.onabort=this.onerror=this.oncomplete=null};r.prototype.__executeRequests=function(){if(this.__running&&this.mode!==o)return e.DEBUG&&console.log("Looks like the request set is already running",this.mode),void 0;this.__running=!0;var t=this;window.setTimeout(function(){2===t.mode||t.__active||e.util.throwDOMException(0,"A request was placed against a transaction which is currently not active, or which is finished",t.__active),t.db.__db.transaction(function(n){function o(t,n){n&&(a.req=n),a.req.readyState="done",a.req.result=t,delete a.req.error;var o=e.Event("success");e.util.callback("onsuccess",a.req,o),s++,i()}function r(){a.req.readyState="done",a.req.error="DOMError";var t=e.Event("error",arguments);e.util.callback("onerror",a.req,t),s++,i()}function i(){return s>=t.__requests.length?(t.__active=!1,t.__requests=[],void 0):(a=t.__requests[s],a.op(n,a.args,o,r),void 0)}t.__tx=n;var a=null,s=0;try{i()}catch(c){e.DEBUG&&console.log("An exception occured in transaction",arguments),"function"==typeof t.onerror&&t.onerror()}},function(){e.DEBUG&&console.log("An error in transaction",arguments),"function"==typeof t.onerror&&t.onerror()},function(){e.DEBUG&&console.log("Transaction completed",arguments),"function"==typeof t.oncomplete&&t.oncomplete()})},1)},r.prototype.__addToTransactionQueue=function(t,n){this.__active||this.mode===o||e.util.throwDOMException(0,"A request was placed against a transaction which is currently not active, or which is finished.",this.__mode);var r=this.__createRequest();return this.__pushToQueue(r,t,n),r},r.prototype.__createRequest=function(){var t=new e.IDBRequest;return t.source=this.db,t.transaction=this,t},r.prototype.__pushToQueue=function(e,t,n){this.__requests.push({op:t,args:n,req:e}),this.__executeRequests()},r.prototype.objectStore=function(t){return new e.IDBObjectStore(t,this)},r.prototype.abort=function(){!this.__active&&e.util.throwDOMException(0,"A request was placed against a transaction which is currently not active, or which is finished",this.__active)},r.prototype.READ_ONLY=0,r.prototype.READ_WRITE=1,r.prototype.VERSION_CHANGE=2,e.IDBTransaction=r}(idbModules),function(e){var t=function(t,n,o,r){this.__db=t,this.version=o,this.objectStoreNames=new e.util.StringList;for(var i=0;r.rows.length>i;i++)this.objectStoreNames.push(r.rows.item(i).name);for(this.__storeProperties={},i=0;r.rows.length>i;i++){var a=r.rows.item(i),s=this.__storeProperties[a.name]={};s.keyPath=a.keypath,s.autoInc="true"===a.autoInc,s.indexList=JSON.parse(a.indexList)}this.name=n,this.onabort=this.onerror=this.onversionchange=null};t.prototype.createObjectStore=function(t,n){var o=this;n=n||{},n.keyPath=n.keyPath||null;var r=new e.IDBObjectStore(t,o.__versionTransaction,!1),i=o.__versionTransaction;i.__addToTransactionQueue(function(i,a,s){function c(){e.util.throwDOMException(0,"Could not create new object store",arguments)}o.__versionTransaction||e.util.throwDOMException(0,"Invalid State error",o.transaction);var u=["CREATE TABLE",e.util.quote(t),"(key BLOB",n.autoIncrement?", inc INTEGER PRIMARY KEY AUTOINCREMENT":"PRIMARY KEY",", value BLOB)"].join(" ");e.DEBUG&&console.log(u),i.executeSql(u,[],function(e){e.executeSql("INSERT INTO __sys__ VALUES (?,?,?,?)",[t,n.keyPath,n.autoIncrement?!0:!1,"{}"],function(){r.__setReadyState("createObjectStore",!0),s(r)},c)},c)}),o.objectStoreNames.push(t);var a=o.__storeProperties[t]={};return a.keyPath=n.keyPath,a.autoInc=!!n.autoIncrement,a.indexList={},r},t.prototype.deleteObjectStore=function(t){var n=function(){e.util.throwDOMException(0,"Could not delete ObjectStore",arguments)},o=this;!o.objectStoreNames.contains(t)&&n("Object Store does not exist"),o.objectStoreNames.splice(o.objectStoreNames.indexOf(t),1);var r=o.__versionTransaction;r.__addToTransactionQueue(function(){o.__versionTransaction||e.util.throwDOMException(0,"Invalid State error",o.transaction),o.__db.transaction(function(o){o.executeSql("SELECT * FROM __sys__ where name = ?",[t],function(o,r){r.rows.length>0&&o.executeSql("DROP TABLE "+e.util.quote(t),[],function(){o.executeSql("DELETE FROM __sys__ WHERE name = ?",[t],function(){},n)},n)})})})},t.prototype.close=function(){},t.prototype.transaction=function(t,n){var o=new e.IDBTransaction(t,n||1,this);return o},e.IDBDatabase=t}(idbModules),function(e){var t=4194304;if(window.openDatabase){var n=window.openDatabase("__sysdb__",1,"System Database",t);n.transaction(function(e){e.executeSql("CREATE TABLE IF NOT EXISTS dbVersions (name VARCHAR(255), version INT);",[])},function(){e.DEBUG&&console.log("Error in sysdb transaction - when creating dbVersions",arguments)});var o={open:function(o,r){function i(){if(!c){var t=e.Event("error",arguments);s.readyState="done",s.error="DOMError",e.util.callback("onerror",s,t),c=!0}}function a(a){var c=window.openDatabase(o,1,o,t);s.readyState="done",r===void 0&&(r=a||1),(0>=r||a>r)&&e.util.throwDOMException(0,"An attempt was made to open a database using a lower version than the existing version.",r),c.transaction(function(t){t.executeSql("CREATE TABLE IF NOT EXISTS __sys__ (name VARCHAR(255), keyPath VARCHAR(255), autoInc BOOLEAN, indexList BLOB)",[],function(){t.executeSql("SELECT * FROM __sys__",[],function(t,u){var d=e.Event("success");s.source=s.result=new e.IDBDatabase(c,o,r,u),r>a?n.transaction(function(t){t.executeSql("UPDATE dbVersions set version = ? where name = ?",[r,o],function(){var t=e.Event("upgradeneeded");t.oldVersion=a,t.newVersion=r,s.transaction=s.result.__versionTransaction=new e.IDBTransaction([],2,s.source),e.util.callback("onupgradeneeded",s,t,function(){var t=e.Event("success");e.util.callback("onsuccess",s,t)})},i)},i):e.util.callback("onsuccess",s,d)},i)},i)},i)}var s=new e.IDBOpenRequest,c=!1;return n.transaction(function(e){e.executeSql("SELECT * FROM dbVersions where name = ?",[o],function(e,t){0===t.rows.length?e.executeSql("INSERT INTO dbVersions VALUES (?,?)",[o,r||1],function(){a(0)},i):a(t.rows.item(0).version)},i)},i),s},deleteDatabase:function(o){function r(t){if(!s){a.readyState="done",a.error="DOMError";var n=e.Event("error");n.message=t,n.debug=arguments,e.util.callback("onerror",a,n),s=!0}}function i(){n.transaction(function(t){t.executeSql("DELETE FROM dbVersions where name = ? ",[o],function(){a.result=void 0;var t=e.Event("success");t.newVersion=null,t.oldVersion=c,e.util.callback("onsuccess",a,t)},r)},r)}var a=new e.IDBOpenRequest,s=!1,c=null;return n.transaction(function(n){n.executeSql("SELECT * FROM dbVersions where name = ?",[o],function(n,s){if(0===s.rows.length){a.result=void 0;var u=e.Event("success");return u.newVersion=null,u.oldVersion=c,e.util.callback("onsuccess",a,u),void 0}c=s.rows.item(0).version;var d=window.openDatabase(o,1,o,t);d.transaction(function(t){t.executeSql("SELECT * FROM __sys__",[],function(t,n){var o=n.rows;(function a(n){n>=o.length?t.executeSql("DROP TABLE __sys__",[],function(){i()},r):t.executeSql("DROP TABLE "+e.util.quote(o.item(n).name),[],function(){a(n+1)},function(){a(n+1)})})(0)},function(){i()})},r)})},r),a},cmp:function(t,n){return e.Key.encode(t)>e.Key.encode(n)?1:t===n?0:-1}};e.shimIndexedDB=o}}(idbModules),function(e,t){e.openDatabase!==void 0&&(e.shimIndexedDB=t.shimIndexedDB,e.shimIndexedDB&&(e.shimIndexedDB.__useShim=function(){e.indexedDB=t.shimIndexedDB,e.IDBDatabase=t.IDBDatabase,e.IDBTransaction=t.IDBTransaction,e.IDBCursor=t.IDBCursor,e.IDBKeyRange=t.IDBKeyRange,e.indexedDB!==t.shimIndexedDB&&Object.defineProperty&&Object.defineProperty(e,"indexedDB",{value:t.shimIndexedDB})},e.shimIndexedDB.__debug=function(e){t.DEBUG=e})),"indexedDB"in e||(e.indexedDB=e.indexedDB||e.webkitIndexedDB||e.mozIndexedDB||e.oIndexedDB||e.msIndexedDB);var n=!1;if((navigator.userAgent.match(/Android 2/)||navigator.userAgent.match(/Android 3/)||navigator.userAgent.match(/Android 4\.[0-3]/))&&(navigator.userAgent.match(/Chrome/)||(n=!0)),void 0!==e.indexedDB&&!n||void 0===e.openDatabase){e.IDBDatabase=e.IDBDatabase||e.webkitIDBDatabase,e.IDBTransaction=e.IDBTransaction||e.webkitIDBTransaction,e.IDBCursor=e.IDBCursor||e.webkitIDBCursor,e.IDBKeyRange=e.IDBKeyRange||e.webkitIDBKeyRange,e.IDBTransaction||(e.IDBTransaction={});try{e.IDBTransaction.READ_ONLY=e.IDBTransaction.READ_ONLY||"readonly",e.IDBTransaction.READ_WRITE=e.IDBTransaction.READ_WRITE||"readwrite"}catch(o){}}else e.shimIndexedDB.__useShim()}(window,idbModules);
// TODO: when IdxDBShim updates, you need to change 4194304 (4MB) to 104857600 (100MB) by hand

// iOS8 home screen apps are doing weird things with indexeddb
var indexedDBSafe = window.indexedDB || window.mozIndexedDB || window.webkitIndexedDB || window.msIndexedDB || window.shimIndexedDB;
if(navigator.standalone) {
  if(window.shimIndexedDB) {
    window.shimIndexedDB.__useShim();
  }
  // indexedDBSafe = window.shimIndexedDB;
}

window.cd_request_file_system = window.webkitRequestFileSystem || window.requestFileSystem;
window.cd_persistent_storage = window.navigator.webkitPersistentStorage || window.navigator.persistentStorage;

var capabilities;
(function() {
  var console_debug = function(str) {
    if(console.debug) {
      console.debug(str);
    } else {
      console.log(str);
    }
  };
  var ajax = $.ajax;
  var chrome;

  function message_client(message) {
    if(window.coughDropExtras) {
      window.coughDropExtras.extension_message(message);
    }
  }

  capabilities = window.capabilities || {};
  capabilities.fallback_host = 'https://app.mycoughdrop.com';
  capabilities.installed_app = !!capabilities.installed_app;
  capabilities.browserless = !!(capabilities.installed_app || navigator.standalone);
  capabilities.queued_db_actions = [];
  // TODO: maybe https://github.com/VJAI/simple-crypto
  capabilities.encryption_enabled = !!window.CryptoJS;
  if(!capabilities.system) {
    capabilities.system = "Desktop";
    capabilities.browser = "Web browser";
    capabilities.mobile = false;
    if(navigator.userAgent.match(/ipod|ipad|iphone/i)) {
      capabilities.mobile = true;
      capabilities.system = "iOS";
      if(capabilities.installed_app) {
        capabilities.browser = "App";
      } else if(navigator.userAgent.match(/crios/i)) {
        capabilities.browser = "Chrome";
      } else if(navigator.userAgent.match(/safari/i)) {
        capabilities.browser = "Safari";
      }
      var version = navigator.userAgent.match(/OS\s+([\d_]+)\s+like/)[1];
      version = parseInt(version && version.split(/_/)[0], 10);
      if(version && isFinite(version)) {
        capabilities.system_version = version;
      }
    } else if(navigator.userAgent.match(/android/i)) {
      capabilities.mobile = true;
      capabilities.system = "Android";
      if(capabilities.installed_app) {
        capabilities.browser = "App";
        if(window.device && window.device.platform && window.device.platform.match(/fireos/i)) {
          capabilities.subsystem = "Kindle";
        }
      } else if(navigator.userAgent.match(/chrome/i)) {
        capabilities.browser = "Chrome";
      }
    } else if(navigator.userAgent.match(/windows phone/i)) {
      capabilities.mobile = true;
      capabilities.system = "Windows Phone";
    } else {
      if(navigator.userAgent.match(/macintosh/i)) {
        capabilities.system = "Mac";
      } else if(navigator.userAgent.match(/windows\snt/i)) {
        capabilities.system = "Windows";
      } else if(navigator.userAgent.match(/CoughDrop Desktop App/)) {
        capabilities.system = "Windows";
        capabilities.browser = "App";
      }
      if(navigator.userAgent.match(/chrome/i)) {
        capabilities.browser = "Chrome";
      } else if(navigator.userAgent.match(/firefox/i)) {
        capabilities.browser = "Firefox";
      } else if(navigator.userAgent.match(/msie/i)) {
        capabilities.browser = "IE";
      } else if(navigator.userAgent.match(/edge/i)) {
        capabilities.browser = "Edge";
      }
    }
    capabilities.readable_device_name = capabilities.readable_device_name || (capabilities.browser + " for " + capabilities.system);
  }
  if(capabilities.encryption_enabled) {
    console_debug("COUGHDROP: indexedDB encryption is enabled");
  }
  (function() {
    var functions = {
      init: function() {
        if(this.client_ready) { return; }
        this.client_ready = true;

        window.capabilities = capabilities;
        capabilities.host = capabilities.system_host;
        var auth_settings = stashes.get_object('auth_settings', true) || {};
        if(capabilities.api_host) {
          console_debug("COUGHDROP: extension connected, pointing requests to " + capabilities.api_host);
        }
        capabilities.db_key = stashes.get_db_key();
        var res = true;
        if(indexedDBSafe) {
          res = capabilities.setup_database();
        }
        capabilities.credentials = capabilities.auth_credentials;
        capabilities.access_token = auth_settings.access_token;
        if(window.Keyboard && window.Keyboard.shrinkView) {
          window.Keyboard.shrinkView(false);
        }

        return res;
      },
      eye_gaze: {
        listen: function() {
        },
        stop_listening: function() {
        },
        calibrate: function() {
        },
        calibratable: function(cb) {
          cb(false);
        }
      },
      encrypt: function(obj) {
        if(capabilities.encryption_enabled) {
          alert('encryption not supported');
          return window.CryptoJS.AES.encrypt(JSON.stringify(obj), capabilities.db_key).toString();
        } else {
          return JSON.stringify(obj);
        }
      },
      decrypt: function(obj) {
        if(capabilities.encryption_enabled) {
          alert('encryption not supported');
          return JSON.parse(window.CryptoJS.AES.decrypt(obj, capabilities.db_key).toString(window.CryptoJS.enc.Utf8));
        } else {
          return JSON.parse(obj);
        }
      },
      nfc: {
        available: function() {
          var promise = capabilities.mini_promise();
          if(window.nfc && window.nfc.enabled) {
            window.nfc.enabled(function() { 
              var res = {nfc: true, background: true};
              if(capabilities.system == 'iOS') {
                res.background = false;
              }
              if(capabilities.system == 'Android') {
                res.can_write = true;
              }
              promise.resolve(res); 
            }, function() { promise.reject(); });
          } else {
            promise.reject();
          }
          return promise;
        },
        prompt: function() {
          var promise = capabilities.mini_promise();
          if(window.nfc && window.nfc.beginSession && capabilities.system == 'iOS') {
            window.nfc.beginSession(function() { promise.resolve(); }, function() { promise.reject({error: 'session failed'}); });
          } else if(window.nfc && window.nfc.enabled) {
            return capabilities.nfc.available();
          } else {
            promise.reject({error: 'no NFC support found'});
          }
          return promise;
        },
        end_prompt: function() {
          var promise = capabilities.mini_promise();
          if(window.nfc && window.nfc.invalidateSession && capabilities.system == 'iOS') {
            window.nfc.invalidateSession(function() { promise.resolve(); }, function() { promise.reject({error: 'session failed'}); });
          } else if(window.nfc && window.nfc.enabled) {
            return capabilities.nfc.available();
          } else {
            promise.reject({error: 'no NFC support found'});
          }
          return promise;
        },
        write: function(tag) {
          var promise = capabilities.mini_promise();
          if(window.nfc && window.nfc.write && window.ndef) {
            var message = [];
            if(tag.text) { message.push(window.ndef.textRecord(tag.text)); }
            if(tag.uri) { message.push(window.ndef.uriRecord(tag.uri)); }
            window.nfc.write(message, function() {
              promise.resolve(tag);
            }, function() {
              promise.reject();
            })
          } else {
            promise.reject({error: 'no NFC support found'});
          }
          return promise;
        },
        listen: function(ref, callback) {
          // can't return promise because .write must be called
          // from within the callback scope to work correctly
          var promise = capabilities.mini_promise();
          if(window.nfc && window.nfc.addNdefListener && window.ndef) {
            var listener = function(event) {
              if(event.type == 'ndef' && event.tag) {
                if(event.tag.ndefMessage) {
                  var tag = {type: 'ndef', id: event.tag.id, size: event.tag.maxSize};
                  if(event.tag.isWritable) {
                    tag.writable = true;
                  }
                  for(var idx = 0; idx < event.tag.ndefMessage.length; idx++) {
                    var type = String.fromCharCode.apply(null, event.tag.ndefMessage[idx].type);
                    var payload = String.fromCharCode.apply(null, event.tag.ndefMessage[idx].payload);
                    if(type == 'T' && !tag.text) {
                      tag.text_locale = payload.slice(0, 3);
                      tag.text = payload.slice(3);
                    } else if(type == 'U' && !tag.uri) {
                      tag.uri = payload;
                    }
                  }
                  console.log("NFC tag", tag, event.tag);
                  callback(tag);
                }
              } else {
                console.log("Non-NFC tag", event.type, event.tag);
                callback({type: event.type, id: event.tag.id});
              }
            };
            ref = ref || "whatever";
            capabilities.nfc.listeners = capabilities.nfc.listeners || {};
            capabilities.nfc.listeners[ref] = capabilities.nfc.listeners[ref] || [];
            capabilities.nfc.listeners[ref].push(listener);
            window.nfc.addNdefListener(listener, function() { }, function() {
              promise.reject({error: 'nfc listen failed'});
            });
            window.nfc.addTagDiscoveredListener(listener);
            if(capabilities.system == 'Android') {
              window.nfc.readerMode(nfc.FLAG_READER_NFC_A | nfc.FLAG_READER_NFC_B | nfc.FLAG_READER_NO_PLATFORM_SOUNDS, function(tag) {
                if(navigator && navigator.vibrate) {
                  navigator.vibrate(200);
                }
                for(var key in capabilities.nfc.listeners) {
                  (capabilities.nfc.listeners[key] || []).forEach(function(l) {
                    l({type: 'ndef', tag: tag});
                  });
                }
              }, function() { promise.reject({error: 'NFC reader mode failed'})});
            }
          } else {
            promise.reject({error: 'no NFC support found'});
          }
          return promise;
        },
        stop_listening: function(ref) {
          ref = ref || "whatever";
          capabilities.nfc.listeners = capabilities.nfc.listeners || {};
          capabilities.nfc.listeners[ref] = capabilities.nfc.listeners[ref] || [];
          (capabilities.nfc.listeners[ref] || []).forEach(function(l) {
            window.nfc.removeNdefListener(l);
            window.nfc.removeTagDiscoveredListener(l);
          });
          capabilities.nfc.listeners[ref] = [];
          var all_empty = true;
          for(var key in capabilities.nfc.listeners) {
            if(capabilities.nfc.listeners[key] && capabilities.nfc.listeners[key].length > 0) {
              all_empty = false;
            }
          }
          if(capabilities.system == 'Android' && all_empty) {
            window.nfc.disableReaderMode();
          }
        }
      },
      output: {
        set_target_exec: function(target) {
          var promise = capabilities.mini_promise();
          if(window.cordova && window.cordova.exec && capabilities.installed_app && (capabilities.system == 'Android' || capabilities.system == 'iOS')) {
            window.cordova.exec(function(res) {
              var delay = (res && res.delay) || 0;
              setTimeout(function() {
                promise.resolve(res);
              }, delay);
            }, function(err) {
              promise.reject({error: 'cordova exec failed'});
            }, 'CoughDropMisc', 'setAudioMode', [target]);
          } else {
            promise.reject({error: 'no target handling defined'});
          }
          return promise;
        },
        set_target: function(target) {
          if(target == 'headset_or_earpiece') {
            var promise = capabilities.mini_promise();
            capabilities.output.get_targets().then(function(list) {
              var has_external = list.find(function(i) { return i == 'bluetooth' || i == 'headset'});
              var new_target = 'earpiece';
              if(has_external) {
                new_target = 'headset';
              }
              capabilities.output.set_target_exec(new_target).then(function(res) {
                promise.resolve(res);
              }, function(err) {
                promise.reject(err);
              });
            }, function(err) {
              promise.reject({error: 'failed to retrieve targets'});
            });
            return promise;
          } else {
            return capabilities.output.set_target_exec(target);
          }
        },
        get_targets: function() {
          var promise = capabilities.mini_promise();
          if(window.cordova && window.cordova.exec && capabilities.installed_app && (capabilities.system == 'Android' || capabilities.system == 'iOS')) {
            window.cordova.exec(function(res) {
              promise.resolve(res);
            }, function(err) {
              promise.resolve([]);
            }, 'CoughDropMisc', 'getAudioDevices', []);
          } else {
            promise.resolve([]);
          }
          return promise;
        }
      },
      tts: {
        tts_exec: function(method, args, callback) {
          var promise = capabilities.mini_promise();
          if(window.cordova && window.cordova.exec) {
            var all_args = [];
            if(args) { all_args = [args]; }
            window.cordova.exec(function(res) {
              callback(promise, res);
            }, function(err) {
              promise.reject({error: 'cordova exec failed'});
            }, 'ExtraTTS', method, all_args);
          } else if(window.extra_tts) {
            args = args || {};
            args.success = function(res) {
              callback(promise, res);
            };
            args.error = function(str) {
              promise.reject({error: str});
            };
            args.acapela_version = parseFloat(window.acapela_versions['Windows']);
            window.extra_tts[method](args);
          } else {
            promise.reject({erorr: 'platform-level tts not available'});
          }
          return promise;
        },
        downloadable_voices: function() {
          return tts_voices.all();
        },
        init: function() {
          return capabilities.tts.tts_exec('init', null, function(promise, res) {
            promise.resolve(res);
          });
        },
        reload: function() {
          return capabilities.tts.tts_exec('reload', null, function(promise, res) {
            promise.resolve(res);
          });
        },
        status: function() {
          return capabilities.tts.tts_exec('status', null, function(promise, res) {
            promise.resolve(res);
          });
        },
        available_voices: function() {
          return capabilities.tts.tts_exec('getAvailableVoices', null, function(promise, res) {
            promise.resolve(res);
          });
        },
        download_voice: function(voice_id, voice_url, progress) {
          var voice = tts_voices.find_voice(voice_id);
          return capabilities.tts.tts_exec('downloadVoice',
            {
              voice_id: voice_id,
              voice_url: voice_url,
              language_dir: voice.language_dir,
              language_url: voice.windows_language_url,
              binary_url: voice.windows_binary_url,
              voice_size: (capabilities.system == 'Windows' ? (voice.windows_size || (voice.size * 2)) : voice.size)
            },
            function(promise, res) {
              if(res.done) {
                var downloaded = stashes.get('downloaded_voices') || [];
                downloaded.push(voice_id + "::v" + (tts_voices.get('versions.' + capabilities.system) || 'x'));
                stashes.persist('downloaded_voices', downloaded);
                promise.resolve(res);
              } else {
                if(progress) {
                  progress(res);
                }
              }
            }
          );
        },
        delete_voice: function(voice_id) {
          var voice = tts_voices.find_voice(voice_id);
          if(voice) {
            return capabilities.tts.tts_exec('deleteVoice',
            {
              voice_id: voice.voice_id,
              voice_dir: voice.stored_voice_dir || voice.voice_dir,
              language_dir: voice.language_dir
            },
            function(promise, res) {
              var downloaded = stashes.get('downloaded_voices') || [];
              downloaded = downloaded.filter(function(id) { return !id.match(voice_id); });
              stashes.persist('downloaded_voices', downloaded);
              promise.resolve(res);
            });
          } else {
            var promise = capabilities.mini_promise();
            promise.reject("voice not recognized");
            return promise;
          }
        },
        speak_text: function(text, opts) {
          var args = {
            text: text.toString(),
            voice_id: opts.voice_id,
            pitch: opts.pitch,
            rate: opts.rate,
            volume: opts.volume
          };
          return capabilities.tts.tts_exec('speakText', args, function(promise, res) {
            promise.resolve(res);
          });
        },
        stop_text: function() {
          return capabilities.tts.tts_exec('stopSpeakingText', null, function(promise, res) {
            promise.resolve(res);
          });
        }
      },
      sharing: {
        types: function() {
          return {
            'facebook': {
              'Android': 'com.facebook.katana',
              'iOS': 'com.apple.social.facebook'
            },
            'twitter': {
              'iOS': 'com.apple.social.twitter'
            },
            'google_plus': {
              'Android': 'com.google.android.apps.plus',
              'iOS': 'com.google.android.apps.plus'
            }
          };
        },
        available: function() {
          var promise = capabilities.mini_promise();
          // https://github.com/EddyVerbruggen/SocialSharing-PhoneGap-Plugin
          if(window.plugins && window.plugins.socialsharing && window.plugins.socialsharing.canShareVia) {
            setTimeout(function() {
              if(!promise.resolved) {
                promise.resolve([]);
              }
            }, 500);
            var dones = 0;
            var valids = ['generic'];
            if(window.cordova && window.cordova.plugins && window.cordova.plugins.clipboard && window.cordova.plugins.clipboard.copy) {
              valids.push('clipboard');
            }
            if(capabilities.system == 'Android') { valids.push('email'); }
            var all_done = function() {
              dones++;
              if(dones >= checks.length) {
                promise.resolve(valids);
              }
            };
            var check_one = function(type) {
              var check_type = (capabilities.sharing.types()[type] || {})[capabilities.system] || type;
              window.plugins.socialsharing.canShareVia(check_type, 'message', 'message', 'https://www.mycoughdrop.com/images/logo-big.png', 'https://www.mycoughdrop.com', function() {
                valids.push(type);
                all_done();
              }, function() {
                all_done();
              });
            };
            var checks = ['facebook', 'twitter', 'instagram', 'google_plus'];
            checks.forEach(function(type) {
              check_one(type);
            });
          } else {
            promise.resolve([]);
          }
          return promise;
        },
        share: function(type, message, url, image_url) {
          var promise = capabilities.mini_promise();
          var share_type = (capabilities.sharing.types()[type] || {})[capabilities.system] || type;
          if(type == 'email') {
            if(window.plugins && window.plugins.socialsharing && window.plugins.socialsharing.shareViaEmail) {
              window.plugins.socialsharing.shareViaEmail(message, message, null, null, null, [url], function(success) {
                promise.resolve();
              }, function(err) {
                promise.resolve();
              });
            } else {
              promise.reject();
            }
          } else if(type == 'clipboard') {
            // https://github.com/VersoSolutions/CordovaClipboard
            if(window.cordova && window.cordova.plugins && window.cordova.plugins.clipboard && window.cordova.plugins.clipboard.copy) {
              window.cordova.plugins.clipboard.copy(message);
              promise.resolve();
            } else {
              promise.reject();
            }
          } else if(type == 'generic' && window.plugins && window.plugins.socialsharing && window.plugins.socialsharing.share) {
            window.plugins.socialsharing.share(message, message, image_url, url, function(success) {
              promise.resolve();
            }, function(err) {
              promise.resolve();
            });
          } else if(type != 'generic' && window.plugins && window.plugins.socialsharing && window.plugins.socialsharing.shareVia) {
            window.plugins.socialsharing.shareVia(share_type, message, message, image_url, url, function(success) {
              promise.resolve();
            }, function(err) {
              promise.resolve();
            });
          } else {
            promise.reject();
          }
          return promise;
        }
      },
      storage: {
        status: function() {
          // uses native calls
          var promise = capabilities.mini_promise();
          if(window.resolveLocalFileSystemURL && window.cordova && window.cordova.file && window.cordova.file.dataDirectory) {
            promise.resolve({available: true, requires_confirmation: false});
          } else if(window.file_storage) {
            promise.resolve({available: true, requires_confirmation: false});
          } else if(window.cd_request_file_system && window.cd_persistent_storage && window.cd_persistent_storage.requestQuota) {
            // Chrome won't allow storing to the file system in incognito, but still
            // acts like it will. This is the only check I can find that correctly
            // fails in incognito but not in regular browsing mode.
            window.cd_request_file_system(window.TEMPORARY, 100, function(r) {
              window.cd_persistent_storage.queryUsageAndQuota(function(used, requested) {
                if(requested && requested > 0) {
                  promise.resolve({available: true, requires_confirmation: false});
                } else {
                  promise.resolve({available: true, requires_confirmation: true});
                }
              }, function(e) {
                promise.resolve({available: false});
              });
            }, function(err) {
              promise.resolve({available: false});
            });
          } else {
            promise.resolve({available: false});
          }
          return promise;
        },
        clear: function() {
          var promise = capabilities.mini_promise();
          capabilities.storage.all_files().then(function(list) {
            var cleared = 0;
            list.forEach(function(file) {
              capabilities.storage.remove_file(file.dir, file.name).then(function() {
                cleared++;
                if(cleared == list.length) {
                  capabilities.cached_dirs = {};
                  promise.resolve(list.length);
                }
              }, function(err) {
                if(cleared > 0) { capabilities.cached_dirs = {}; }
                promise.reject(err);
              });
            });
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        all_files: function() {
          // uses native calls
          var promise = capabilities.mini_promise();
          var all_files = [];
          var size = 0;
          capabilities.storage.root_entry().then(function(root) {
            var dirs = [];
            var reader = root.createReader();
            reader.readEntries(function(list) {
              list.forEach(function(e) {
                if(e.isDirectory) {
                  dirs.push(e.name);
                }
              });
              var done_dirs = 0;
              dirs.forEach(function(dir) {
                capabilities.storage.list_files(dir, true).then(function(list) {
                  done_dirs++;
                  list.forEach(function(file) {
                    all_files.push({
                      name: file,
                      dir: dir
                    });
                  });
                  size = size + (list.size || 0);
                  if(done_dirs == dirs.length) {
                    all_files.size = size;
                    promise.resolve(all_files);
                  }
                }, function(err) {
                  promise.reject(err);
                });
              });
            }, function(err) {
              promise.reject(err);
            });
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        assert_directory: function(key, filename) {
          // uses native calls
          var promise = capabilities.mini_promise();
          var sub_key = filename ? filename.substring(0, 4) : null;
          var path = filename ? (key + '/' + sub_key) : key;
          capabilities.cached_dirs = capabilities.cached_dirs || {};
          if(capabilities.cached_dirs[path]) {
            promise.resolve(capabilities.cached_dirs[path]);
          } else {
            var find_sub_dir = function(dir) {
              if(filename) {
                dir.getDirectory(sub_key, {create: true}, function(sub_dir) {
                  capabilities.cached_dirs[path] = sub_dir;
                  promise.resolve(sub_dir);
                }, function(err) {
                  promise.reject(err);
                });
              } else {
                promise.resolve(dir);
              }
            };
            if(capabilities.cached_dirs[key]) {
              find_sub_dir(capabilities.cached_dirs[key]);
            } else {
              capabilities.storage.root_entry().then(function(root) {
                root.getDirectory(key, {create: true}, function(dir) {
                  capabilities.cached_dirs[key] = dir;
                  find_sub_dir(dir);
                }, function(err) {
                  promise.reject(err);
                });
              }, function(err) { promise.reject(err); });
            }
          }
          return promise;
        },
        list_files: function(dirname, include_size) {
          // uses native calls
          var promise = capabilities.mini_promise();
            if(window.cordova && window.cordova.exec) {
              var dir = window.cordova.file.dataDirectory.replace(/file:\/\//, '') + dirname + '/';
              window.cordova.exec(function(list) {
                var res = [];
                list.files.forEach(function(file) {
                  var fn = file.split(/\//).pop();
                  if(!file.match(/\/$/) && fn.match(/\./)) {
                    res.push(fn);
                  }
                });
                res.size = list.size;
                promise.resolve(res);
              }, function(err) {
                promise.reject(err);
              }, 'CoughDropMisc', 'listFiles', [{dir: dir}]);
              return promise;
            }
          capabilities.storage.assert_directory(dirname).then(function(dir) {
            var res = [];
            res.size = 0;
            var dirs = [dir];
            var next_dir = function(go_deeper) {
              var dir = dirs.shift();
              if(dir) {
                var reader = dir.createReader();
                reader.readEntries(function(list) {
                  var idx = 0;
                  var next_file = function() {
                    var e = list[idx];
                    if(!e) {
                      return next_dir(false);
                    }
                    idx++;
                    if(e.isFile) {
                      if(include_size) {
                        if(e.size && e.size > 0) {
                          res.push(e.name);
                          res.size = res.size + e.size;
                          next_file();
                        } else if(e.getMetadata) {
                          e.getMetadata(function(metadata) {
                            if(metadata.size > 0) {
                              res.push(e.name);
                              res.size = res.size + metadata.size;
                            }
                            next_file();
                          }, function() {
                            next_file();
                          });
                        } else {
                          next_file();
                        }
                      } else {
                        res.push(e.name);
                        next_file();
                      }
                    } else if(e.isDirectory && go_deeper) {
                      dirs.push(e);
                      next_file();
                    } else {
                      next_file();
                    }
                  };
                  next_file();
                }, function(err) {
                  promise.reject(err);
                });
              } else {
                promise.resolve(res);
              }
            };
            next_dir(true);
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        fix_url: function(url) {
          // uses native calls
          if(!window.resolveLocalFileSystemURL) {
            return url;
          }
          var prefix = window.cordova.file.dataDirectory;
          if(url.match("^" + prefix)) {
            return url;
          }
          var re = /Application\/[^\/]+/;
          var prefix_sub = prefix.match(re);
          if(url.match(re) && prefix_sub) {
            url = url.replace(re, prefix_sub[0]);
          }
          return url;
        },
        get_file_url: function(dirname, filename) {
          // uses native calls
          var promise = capabilities.mini_promise();
          capabilities.storage.assert_directory(dirname, filename).then(function(dir) {
            dir.getFile(filename, {create: false}, function(file) {
              promise.resolve(file.toURL());
            }, function(err) {
              promise.reject(err);
            });
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        write_file: function(dirname, filename, blob) {
          // uses native calls
          var promise = capabilities.mini_promise();
          capabilities.storage.assert_directory(dirname, filename).then(function(dir) {
            dir.getFile(filename, {create: true}, function(file) {
              var url = file.toURL();
              file.createWriter(function(writer) {
                writer.onwriteend = function() {
                  promise.resolve(url);
                };
                writer.onerror = function(err) {
                  promise.reject(err);
                };
                if(capabilities.system == 'Android') {
                  var reader = new FileReader();
                  reader.onload = function() {
                    writer.write(this.result);
                  };
                  reader.readAsArrayBuffer(blob);
                } else {
                  writer.write(blob);
                }
              }, function(err) {
                promise.reject(err);
              });
            }, function(err) {
              promise.reject(err);
            });
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        remove_file: function(dirname, filename) {
          // uses native calls
          var promise = capabilities.mini_promise();
          capabilities.storage.assert_directory(dirname, filename).then(function(dir) {
            dir.getFile(filename, {}, function(file) {
              var url = file.toURL();
              file.remove(function() {
                promise.resolve(url);
              }, function(err) {
                promise.reject(err);
              });
            }, function(err) {
              promise.reject(err);
            });
          }, function(err) {
            promise.reject(err);
          });
          return promise;
        },
        root_entry: function(size) {
          // uses native calls
          var promise = capabilities.mini_promise();
          if(window.resolveLocalFileSystemURL && window.cordova && window.cordova.file && window.cordova.file.dataDirectory) {
            if (capabilities.root_dir_entry) {
              promise.resolve(capabilities.root_dir_entry);
            } else {
              window.resolveLocalFileSystemURL(window.cordova.file.dataDirectory, function(e) {
                capabilities.root_dir_entry = e;
                promise.resolve(e);
              }, function(e) {
                promise.reject(e);
              });
            }
          } else if(window.file_storage) {
            if(capabilities.root_dir_entry) {
              promise.resolve(capabilities.root_dir_entry);
            } else {
              window.file_storage.root(function(e) {
                capabilities.root_dir_entry = e;
                promise.resolve(e);
              }, function(e) {
                promise.reject(e);
              });
            }
          } else if(window.cd_request_file_system && window.cd_persistent_storage && window.cd_persistent_storage.requestQuota) {
            var req_size = 1024*1024*50;
            window.cd_persistent_storage.queryUsageAndQuota(function(used, requested) {
              var get_file_system = function() {
                window.cd_request_file_system(window.PERSISTENT, req_size, function(dir) {
                  capabilities.root_dir_entry = dir.root;
                  promise.resolve(dir.root);
                }, function(err) {
                  promise.reject(err);
                });
              };

              var full_size = Math.max(req_size, requested);
              if((full_size - (used || 0)) < (1024*1024*50) || (requested || 0) < (1024*1024*50)) {
                req_size = full_size + (1024*1024*50);
                setTimeout(function() {
                  promise.reject({error: "timeout"});
                }, 5000);
                // Annoying repeat requests for storage was making me miserable
                if(capabilities.storage.already_limited_size) {
                  if(used > 0) {
                    get_file_system();
                  } else {
                    promise.reject({error: "already rejected"});
                  }
                } else {
                  window.cd_persistent_storage.requestQuota(req_size, function(allotted_size) {
                    if(allotted_size < req_size) {
                      capabilities.storage.already_limited_size = true;
                    }
                    if(allotted_size && allotted_size > 0) {
                      get_file_system();
                    } else {
                      promise.reject({error: "rejected"});
                    }
                  }, function(err) {
                    promise.reject(err);
                  });
                }
              } else if(capabilities.root_dir_entry) {
                return promise.resolve(capabilities.root_dir_entry);
              } else {
                req_size = full_size;
                get_file_system();
              }
            }, function(err) {
              promise.reject(err);
            });
          } else {
            promise.reject({error: "not enabled"});
          }
          return promise;
        }
      },
      debugging: {
        available: function() {
          return false;
        },
        show: function() { }
      },
      silent_mode: function() {
        var res = capabilities.mini_promise();
        if(window.cordova && window.cordova.plugins && window.cordova.plugins.SilentMode) {
          window.cordova.plugins.SilentMode.isMuted(function(r) {
            res.resolve(true);
          }, function() {
            res.resolve(false);
          });
        } else {
          res.resolve(false);
        }
        return res;
      },
      ssid: {
        listen: function(callback) {
          capabilities.ssid_callbacks = capabilities.ssid_callbacks || [];
          var start_listening = capabilities.ssid_callbacks.length === 0;
          capabilities.ssid_callbacks.push(callback);
          var notify_all = function(ssid) {
            ssid = ssid || null;
            if(capabilities.ssid_callbacks) {
              capabilities.ssid_callbacks.forEach(function(cb) {
                if(cb.last_result === undefined || cb.last_result != ssid) {
                  cb(ssid);
                }
              });
            }
          };
          if(start_listening) {
            setInterval(function() {
              // poll
              notify_all(null);
            }, 5000);
          }
        }
      },
      battery: {
        listen: function(callback) {
          capabilities.battery_callbacks = capabilities.battery_callbacks || [];
          var start_listening = capabilities.battery_callbacks.length === 0;
          capabilities.battery_callbacks.push(callback);
          if(start_listening) {
            var notify = function() {
              if(capabilities.battery_callbacks.last_result) {
                var res = {
                  level: capabilities.battery_callbacks.last_result.level,
                  charging: capabilities.battery_callbacks.last_result.charging
                };
                capabilities.battery_callbacks.forEach(function(cb) {
                  cb(res);
                });
              }
            };
            if(navigator.getBattery) {
              navigator.getBattery().then(function(battery) {
                battery.addEventListener('chargingchange', function() {
                  capabilities.battery_callbacks.last_result = capabilities.battery_callbacks.last_result || {};
                  capabilities.battery_callbacks.last_result.charging = battery.charging;
                  notify();
                });
                battery.addEventListener('levelchange', function() {
                  capabilities.battery_callbacks.last_result = capabilities.battery_callbacks.last_result || {};
                  capabilities.battery_callbacks.last_result.level = battery.level;
                  notify();
                });
                if(battery.level) {
                  capabilities.battery_callbacks.last_result = capabilities.battery_callbacks.last_result || {};
                  capabilities.battery_callbacks.last_result.level = battery.level;
                  capabilities.battery_callbacks.last_result.charging = battery.charging;
                  notify();
                }
              });
            }
            document.addEventListener('deviceready', function() {
              window.addEventListener('batterystatus', function(data) {
                if(data && data.level) {
                  capabilities.battery_callbacks.last_result = capabilities.battery_callbacks.last_result || {};
                  capabilities.battery_callbacks.last_result.level = data.level / 100;
                  capabilities.battery_callbacks.last_result.charging = data.isPlugged ? true : undefined;
                  notify();
                }
              }, false);
            });
            if(window.cordova && window.cordova.exec) {
              setTimeout(function() {
                window.cordova.exec(function(r) { console.log(r); }, function(e) { console.error(e); }, 'Battery', 'updateBatteryStatus', [])
              }, 1000);
            }
          }
          if(capabilities.battery_callbacks.last_result) {
            callback(capabilities.battery_callbacks.last_result);
          }
        }
      },
      wakelock_capable: function() {
        return !!((window.chrome && window.chrome.power && window.chrome.power.requestKeepAwake) || (window.powerManagement && window.powerManagement.acquire));
      },
      wakelock: function(type, enable) {
        capabilities.wakelocks = capabilities.wakelocks || {};
        capabilities.wakelocks[type] = !!enable;
        var any_wakes = false;
        var display_wakes = false;
        for(var idx in capabilities.wakelocks) {
          if(capabilities.wakelocks[idx]) {
            any_wakes = true;
            if(idx.toString().match(/!/)) {
              display_wakes = true;
            }
          }
        }
        if(window.chrome && window.chrome.power && window.chrome.power.requestKeepAwake) {
          if(any_wakes) {
            window.chrome.power.requestKeepAwake(display_wakes ? 'display' : 'system');
          } else {
            window.chrome.power.releaseKeepAwake();
          }
          return true;
        } else if(window.powerManagement && window.powerManagement.acquire) {
          if(capabilities.wakelock.pm_held) {
            window.powerManagement.release(function() { capabilities.wakelock.pm_held = false; }, function() { });
          }
          if(any_wakes) {
            if(display_wakes) {
              window.powerManagement.acquire(function() { capabilities.wakelock.pm_held = true; }, function() { });
            } else {
              window.powerManagement.dim(function() { capabilities.wakelock.pm_held = true; }, function() { });
            }
          } else {
            window.powerManagement.release(function() { }, function() { });
          }
        } else {
          return false;
        }
      },
      update_brightness: function() {
        if(window.cordova && window.cordova.exec && capabilities.system !== 'iOS') {
          window.cordova.exec(function(res) {
            var lux = parseFloat(res);
            if(lux && lux >= 0) {
              capabilities.last_lux = lux;
              stashes.ambient_light = capabilities.last_lux;
            }
          }, function(err) { }, 'CoughDropMisc', 'lux', []);
        }
        if(window.cordova && window.cordova.plugins && window.cordova.plugins.brightness) {
          // https://www.npmjs.com/package/cordova-plugin-brightness
          window.cordova.plugins.brightness.getBrightness(function(val) {
            var brightness = parseFloat(val);
            if(brightness && brightness >= 0) {
              capabilities.last_brightness = brightness;
              stashes.screen_brightness = capabilities.last_brightness;
            }
          });
        } else if(capabilities.check_brightness) {
          // https://www.npmjs.com/package/brightness
          capabilities.check_brightness(function(val) {
            capabilities.last_brightness = val;
            stashes.screen_brightness = capabilities.last_brightness;
          });
        }
      },
      brightness: function() {
        return capabilities.last_brightness;
      },
      orientation: function() {
        // alpha - 0=north, 180=south
        // beta - 0=flat, 90=vertical-facing-left, 270=vertical-facing-right
        // gamma - 0=flat, 90=vertical-upright, 270=vertical-upside-down
        // layout - portrait-primary, portrait-secondary, landscape-primary, landscape-secondary
        return capabilities.last_orientation;
      },
      ambient_light: function() {
        // 0 - evil darkness
        // 1 - full moon
        // 50 - lighted living room/bathroom
        // 100 - overcast day
        // 300 - office lighting
        // 400 - sunset
        // 1000 - overcast day
        // 15000 - full daylight
        // 30000 - direct sun
        return capabilities.last_lux;
      },
      volume_check: function() {
        var res = capabilities.mini_promise();
        if(window.plugin && window.plugin.volume && window.plugin.volume.getVolume) {
          window.plugin.volume.getVolume(function(vol) {
            capabilities.last_volume = vol;
            stashes.volume = capabilities.last_volume;
            res.resolve(vol);
          });
        } else {
          res.reject({error: 'volume not available'});
        }
        return res;
      },
      fullscreen_capable: function() {
        return (window.AndroidFullScreen && window.AndroidFullScreen.isSupported()) ||
                document.body.requestFullscreen || document.body.msRequestFullscreen ||
                document.body.mozRequestFullScreen || document.body.webkitRequestFullscreen ||
                window.full_screen;
      },
      fullscreen: function(enable) {
        var res = capabilities.mini_promise();
        var full_screened = null;
        if(enable) {
          if(window.AndroidFullScreen && window.AndroidFullScreen.isSupported()) {
            window.AndroidFullScreen.immersiveMode(function() { }, function() { });
          } else if(window.full_screen) {
            full_screened = window.full_screen(true);
          } else if (document.body.requestFullscreen) {
            document.body.requestFullscreen();
          } else if (document.body.msRequestFullscreen) {
            document.body.msRequestFullscreen();
          } else if (document.body.mozRequestFullScreen) {
            document.body.mozRequestFullScreen();
          } else if (document.body.webkitRequestFullscreen) {
            document.body.webkitRequestFullscreen();
          }
          setTimeout(function() {
            if(full_screened || document.fullScreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement) {
              res.resolve();
            } else {
              res.reject();
            }
          }, 500);
        } else {
          var fs_element = document.fullScreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement;
          if(window.AndroidFullScreen && window.AndroidFullScreen.isSupported()) {
            window.AndroidFullScreen.showSystemUI(function() { }, function() { });
          } else if(window.full_screen) {
            full_screened = window.full_screen(false);
          } else if(fs_element) {
            try {
              if (document.exitFullscreen) {
                document.exitFullscreen();
              } else if (document.msExitFullscreen) {
                document.msExitFullscreen();
              } else if (document.mozCancelFullScreen) {
                document.mozCancelFullScreen();
              } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
              }
            } catch(e) { }
          }
          setTimeout(function() {
            if(full_screened || document.fullScreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement) {
              res.reject();
            } else {
              res.resolve();
            }
          }, 500);
        }
        return res;
      },
      window_open: function(url, target) {
        // TODO: find a way to style the in-app browser better
        if(window.cordova && window.cordova.InAppBrowser && window.cordova.InAppBrowser.open) {
          window.cordova.InAppBrowser.open(url, target);
        } else {
          if(target == '_system') { target = '_blank'; }
          window.open(url, target);
        }
      },
      storage_clear: function(options) {
        var promise = capabilities.mini_promise();
        if(capabilities.dbman.not_ready(capabilities.storage_clear, options, promise)) { return promise; }

        capabilities.dbman.clear(options.store, function(record) {
          promise.resolve(record);
        }, function(error) {
          promise.reject(error);
        });
        return promise;
      },
      storage_find_changed: function(options) {
        // TODO: needs to clear out deletions table
        var dbs = ['image', 'sound', 'board', 'user'];
        var getters = [];
        var changes = [];
        for(var idx = 0; idx < dbs.length; idx++) {
          getters.push({
            store: dbs[idx],
            index: 'changed',
            value: true
          });
        }
        getters.push({
          store: 'deletion',
          index: null
        });
        var promise = capabilities.mini_promise();

        function next_getter() {
          var getter = getters.shift();
          if(!getter) {
            return clear_deletions();
          }
          capabilities.dbman.find_all(getter.store, getter.index, getter.value, function(res) {
            changes = changes.concat(res);
            setTimeout(function() {
              next_getter();
            }, 500);
          }, function() {
            promise.reject({error: "error retrieving changes from db for " + getter.store});
          });
        }
        next_getter();

        function clear_deletions() {
//           // this belongs as a separate call in sync, not part of find_changed
//           capabilities.dbman.clear('deletion', function() {
            promise.resolve(changes);
//           }, function() {
//             storage_result(false, options.id, {error: 'error cleaning deletions'});
//           });
        }
        return promise;
      },
      mini_promise: function() {
        var promise = {
          resolve: function(result) {
            if(promise.resolved || promise.rejected) { return; }
            promise.resolved = true;
            promise.result = result;
            promise.resolves.forEach(function(resolve) {
              if(resolve) {
                var res = resolve(result);
                if(resolve.next_promise) {
                  resolve.next_promise.resolve(res);
                }
              }
            });
          },
          reject: function(result) {
            if(promise.resolved || promise.rejected) { return; }
            promise.rejected = true;
            promise.result = result;
            promise.rejects.forEach(function(reject) {
              if(reject) {
                var res = reject(result);
                if(reject.next_promise) {
                  reject.next_promise.reject(res);
                }
              }
            });
          },
          resolves: [],
          rejects: [],
          then: function(resolve, reject) {
            var next_promise = capabilities.mini_promise();
            resolve = resolve || function(res) {
              return res;
            };
            reject = reject || function(res) {
              return res;
            };
            if(promise.resolved) {
              if(resolve) {
                var res = resolve(promise.result);
                next_promise.resolve(res);
              }
            } else if(promise.rejected) {
              if(reject) {
                var res = reject(promise.result);
                next_promise.reject(res);
              }
            } else {
              resolve.next_promise = next_promise;
              promise.resolves.push(resolve);
              reject.next_promise = next_promise;
              promise.rejects.push(reject);
            }
            return next_promise;
          }
        };
        return promise;
      },
      storage_find: function(options) {
        var res = capabilities.mini_promise();
        if(capabilities.dbman.not_ready(capabilities.storage_find, options, res)) { return res; }

        capabilities.dbman.find(options.store, options.key, function(record) {
          res.resolve(record);
        }, function(error) {
          res.reject(error);
        });
        return res;
      },
      storage_find_all: function(options) {
        var res = capabilities.mini_promise();
        if(capabilities.dbman.not_ready(capabilities.storage_find_all, options, res)) { return res; }

        var index = null, keys = null;
        if(options.ids) {
          index = 'id';
          keys = options.ids;
        }
        capabilities.dbman.find_all(options.store, index, keys, function(list) {
          res.resolve(list);
        }, function(error) {
          res.reject(error);
        });
        return res;
      },
      storage_store: function(options) {
        var promise = capabilities.mini_promise();
        if(capabilities.dbman.not_ready(capabilities.storage_store, options, promise)) { return promise; }

        capabilities.dbman.store(options.store, options.record, function(record) {
          promise.resolve(record);
        }, function(error) {
          promise.reject(error);
        });
        return promise;
      },
      storage_remove: function(options) {
        var promise = capabilities.mini_promise();
        if(capabilities.dbman.not_ready(capabilities.storage_remove, options, promise)) { return promise; }

        capabilities.dbman.remove(options.store, options.record_id, function(record) {
          promise.resolve(record);
        }, function(error) {
          promise.reject(error);
        });
        return promise;
      },
      push_messaging: function() {
        // https://developer.chrome.com/extensions/pushMessaging.html
      },
      notify: function() {
        // https://developer.chrome.com/extensions/notifications.html
      },
      invoke: function(message) {
        var promise = capabilities.mini_promise();
        if(capabilities[message.method]) {
          var res = capabilities[message.method]( message.options);
          if(res && res.then) { promise = res; }
          else if(res && res.error) {
            promise.reject(res);
          } else {
            promise.resolve(res);
          }
        } else {
          promise.reject({error: "capabilities method not found: " + message.method});
          console_debug("capabilities method not found: " + message.method);
        }
        return promise;
      }
    };
    var function_maker = function(obj, key, fn) {
      obj[key] = function() {
        return fn.apply(capabilities, arguments);
      };
    };
    for(var idx in functions) {
      if(typeof functions[idx] == 'function') {
        function_maker(capabilities, idx, functions[idx]);
      } else {
        capabilities[idx] = {};
        for(var jdx in functions[idx]) {
          function_maker(capabilities[idx], jdx, functions[idx][jdx]);
        }
      }
    }

  })();
  capabilities.sensor_listen = function() {
    if(window.DeviceOrientationEvent) {
      window.addEventListener('deviceorientation', function(event) {
        if(event.alpha !== null && event.alpha !== undefined) {
          var layout = 'unknown';
          // layout - portrait-primary, portrait-secondary, landscape-primary, landscape-secondary
          if(window.screen && window.screen.orientation && window.screen.orientation.type) {
            layout = window.screen.orientation.type;
          } else if(window.orientation !== null && window.orientation !== undefined) {
            var landscape = window.innerWidth > window.innerHeight;
            if(window.orientation === 0 || window.orientation === 90) {
              layout = landscape ? 'landscape-primary' : 'portrait-primary';
            } else if(window.orientation === 180 || window.orientation === -90) {
              layout = landscape ? 'landscape-secondary' : 'portrait-secondary';
            }
          }
          capabilities.last_orientation = {
            alpha: Math.round(event.alpha * 100) / 100,
            beta: Math.round(event.beta * 100) / 100,
            gamma: Math.round(event.gamma * 100) / 100,
            layout: layout,
            timestamp: Math.round((new Date()).getTime() / 1000)
          };
          stashes.orientation = capabilities.last_orientation;
        }
      });
    }
    if(window.plugin && window.plugin.volume && window.plugin.volume.setVolumeChangeCallback) {
      window.plugin.volume.setVolumeChangeCallback(function(vol) {
        capabilities.last_volume = vol;
        stashes.volume = capabilities.last_volume;
      });
    }
    // TODO: https://github.com/brunovilar/cordova-plugins/tree/master/AmbientLight
    setInterval(capabilities.update_brightness, 10000);
    var LightSensor = window.LightSensor || window.AmbientLightSensor;
    if(LightSensor) {
      try {
        // TODO: only track while in speak mode
        var s = new LightSensor();
        s.start();
        s.onchange = function(event) {
          capabilities.last_lux = event.reading && event.reading.illuminance;
          stashes.ambient_light = capabilities.last_lux;
        };
      } catch(e) { }
    }
    window.addEventListener('devicelight', function(event) {
      capabilities.last_lux = event.lux || event.value;
      stashes.ambient_light = capabilities.last_lux;
    });

    // TODO: ProximitySensor?
  };
  capabilities.sensor_listen();

  capabilities.setup_database = function() {
    delete capabilities['db'];
    var user_name = stashes.get_db_id(capabilities);
    var db_key = stashes.get_db_key(true);
    // keep using legacy db ids, but for new dbs don't worry about the key anymore
    if(!db_key || db_key.match(/^db2/)) {
      db_key = "db";
    }
    var key = "coughDropStorage::" + (user_name || "__") + "===" + db_key;
    capabilities.db_name = key;

    var promise = capabilities.mini_promise();

    var setup = capabilities.dbman.setup_database(key, 2);
    setup.then(function(db) {
      // Don't proceed with app initialization until db_connect completes, ensuring
      // stashes is populated with whatever data is available.
      var connect = stashes.db_connect(capabilities);
      connect.then(function() {
        (capabilities.queued_db_actions || []).forEach(function(m) {
          m[0](m[1]).then(function(res) {
            m[2].resolve(res);
          }, function(err) {
            m[2].reject(err);
          });
        });
        capabilities.queued_db_actions = [];
        promise.resolve();
      }, function(err) {
        promise.reject(err);
      });
    }, function(err) {
      promise.reject(err);
    });

    return promise;
  };
  capabilities.delete_database = function() {
    return capabilities.dbman.delete_database(capabilities.db_name).then(function() {
      stashes.persist_raw('cd_db_key', '');
      stashes.get_db_key();
    });
  };
  capabilities.idb = indexedDBSafe;

  capabilities.dbman = dbman;
  capabilities.original_dbman = capabilities.dbman;
})();

export default capabilities;
