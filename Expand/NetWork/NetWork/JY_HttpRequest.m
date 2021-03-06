//
//  JY_HttpRequest.m
//  JYProject
//
//  Created by dayou on 2017/7/31.
//  Copyright © 2017年 dayou. All rights reserved.
//

#import "JY_HttpRequest.h"
#import "JY_HttpRequestResend.h"
#import "JY_HttpResponse.h"
#import "JY_MonitorNewWork.h"

static const NSInteger ResendCount = 3; //允许接口发送次数

@interface JY_HttpRequest()
/* 分派的请求id */
@property (nonatomic ,strong, readwrite)NSMutableArray *requestIdList;

/* 重发分配Id */
@property (nonatomic ,strong)NSNumber *resendId;

@end

@implementation JY_HttpRequest
#pragma mark ---------- Life Cycle ----------
#pragma mark 取消所有请求 避免不必要的消耗
-(void)dealloc{
    [self cancleAllRequest];
    self.requestIdList = nil;
}

#pragma mark ---------- Public Methods ----------
#pragma mark 数据开始请求
- (void)requestWithURLString: (NSString *)URLString
                      method: (JYRequestMethodType)method
                  parameters: (NSDictionary *)parameters
              imageListBlack:(NetWorkUpload)imageListBlack
{
    /* 检验参数 */
    JY_HttpResponse *errorResponse = [self checkRequestInfoWithURLString:URLString method:method parameters:parameters imageListBlack:imageListBlack];
    if (errorResponse) {
        [self failedOnCallingAPI:errorResponse];
        return;
    }
    JY_HttpRequestResend *resend = [self createRequestResendWithAPI:URLString method:method parameters:parameters imageListBlack:imageListBlack];
    if (resend.requestId) {
        [self.requestIdList addObject:resend];
    }
}
#pragma mark 数据重新请求
-(void)resendRequestWithRequestResend:(JY_HttpRequestResend*)requestResend
{
    requestResend.resendResquestCount++;
    requestResend.requestId = [self requestWithRequestResend:requestResend];
}
#pragma mark 数据请求
- (NSNumber*)requestWithRequestResend:(JY_HttpRequestResend*)requestResend
{
    /* 检验网络 */
    JY_HttpResponse *errorResponse = [self checkNetWrok];
    if (errorResponse) {
        errorResponse.baseResponseModel.url = [self getURLStringWithApi:requestResend.apiDetails.api];
        [self failedOnCallingAPI:errorResponse];
        return nil;
    }
    JY_HttpRequest __weak *__self = self;
    NSNumber *requestId = [[JY_HttpProxy sharedRequestInstance] requestWithURLString:requestResend.apiDetails.api method:requestResend.apiDetails.method parameters:requestResend.apiDetails.parameters imageListBlack:requestResend.apiDetails.imageListBlack progressBlock:^(CGFloat currentProgress){
        [__self.delegate managerCallAPIUploadProgressWithCurrentProgress:currentProgress];
    }finishedBlock:^(JY_HttpResponse *response){
           [__self successedOnCallingAPI:response];
   } failureBlock:^(JY_HttpResponse *response) {
       [__self failedOnCallingAPI:response];
   }];
    return requestId;
}
#pragma mark 取消所有数据请求
- (void)cancleAllRequest{
    __block NSMutableArray *requestIds = [[NSMutableArray alloc]initWithCapacity:self.requestIdList.count];
    [self.requestIdList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        JY_HttpRequestResend *resendItem = obj;
        resendItem.resendResquestCount = 3;
        [requestIds addObject:resendItem.requestId];
    }];
    [[JY_HttpProxy sharedRequestInstance] cancleAllRequestWithArrayList:requestIds];
}

#pragma mark ---------- Private Methods ----------
#pragma mark 请求成功回调
-(void)successedOnCallingAPI:(JY_HttpResponse*)response{
    [self failedOnCallingAPI:response];
}

#pragma mark 请求失败回调
-(void)failedOnCallingAPI:(JY_HttpResponse*)response
{
    JY_HttpRequestResend *resend = [self getRequestResendWithResponse:response];
    if (resend) {
        if ((response.baseResponseModel.responseErrorType ==JYResponseErrorTypeDefault ||response.baseResponseModel.responseErrorType ==JYResponseErrorTypeTimeout)&&_notResendResquest != YES) {
            if (resend.resendResquestCount<ResendCount) {
                /* 重新请求 */
                [self resendRequestWithRequestResend:resend];
                return;
            }
            else{
                [self.requestIdList removeObject:resend];
            }
        }
        else{
            [self.requestIdList removeObject:resend];
        }
    }
    
    switch (response.baseResponseModel.responseErrorType) {
        case JYResponseErrorTypeDefault:{
            response.baseResponseModel.message = JY_RequestError;
        }
            break;
        case JYResponseErrorTypeSuccess:{
            response.baseResponseModel.responseData = response.baseResponseModel.responseData;
            if ([response.baseResponseModel.responseData isKindOfClass:[NSDictionary class]]) {
                response.baseResponseModel.message = response.baseResponseModel.responseData[@"message"];
            }
            return [self.delegate managerCallAPIDidSuccess:response.baseResponseModel];
        }
            break;
        case JYResponseErrorTypeNoContent:{
            response.baseResponseModel.message = JY_RequestError;
        }
            break;
        case JYResponseErrorTypeTimeout:{
            response.baseResponseModel.message = JY_RequestOutTime;
        }
            break;
        case JYResponseErrorTypeNoNetWork:{
            response.baseResponseModel.message = JY_RequestNoNetwork;
        }
            break;
        case JYResponseErrorTypeParamsError:{
            response.baseResponseModel.message = JY_RequestError;
        }
            break;
        default:
            break;
    }
    [self.delegate managerCallAPIDidFailed:response.baseResponseModel];
}
#pragma mark 检验参数是否合格
-(JY_HttpResponse*)checkRequestInfoWithURLString:(NSString*)URLString method:(JYRequestMethodType)method parameters: (NSDictionary *)parameters imageListBlack:(NetWorkUpload)imageListBlack{
    JY_HttpResponse *errorResponse = nil;
    switch (method) {
        case JYRequestMethod_Upload:{
            if (imageListBlack==nil) {
                errorResponse = [[JY_HttpResponse alloc]initWithRequestId:nil api:URLString parameters:parameters];
                errorResponse.baseResponseModel.responseErrorType = JYResponseErrorTypeParamsError;
                return errorResponse;
            }
        }
            break;
        default:
            break;
    }
    if (errorResponse) {
        errorResponse.baseResponseModel.url = [self getURLStringWithApi:URLString];
    }
    return errorResponse;
}

#pragma mark 检验网络是否合格
-(JY_HttpResponse*)checkNetWrok{
    JY_HttpResponse *errorResponse = nil;
    BOOL isNetwork = [JY_MonitorNewWork sharedRequestInstance].isNetwork;
    if (!isNetwork) {
        errorResponse = [[JY_HttpResponse alloc]init];
        errorResponse.baseResponseModel.responseErrorType = JYResponseErrorTypeNoNetWork;
    }
    return errorResponse;
}

#pragma mark 初始化 RequestResend
-(JY_HttpRequestResend*)createRequestResendWithAPI:(NSString*)api method: (JYRequestMethodType)method parameters:(NSDictionary*)parameters imageListBlack:(NetWorkUpload)imageListBlack
{
    JY_HttpRequestResend *resend = [JY_HttpRequestResend createRequestResendWithAPI:api method:method parameters:parameters imageListBlack:imageListBlack];
    resend.resendId = [self getDispatchResendId];
    resend.requestId = [self requestWithRequestResend:resend];
    return resend;
}

#pragma mark 获取 RequestResend
-(JY_HttpRequestResend*)getRequestResendWithResponse:(JY_HttpResponse*)response
{
    __block JY_HttpRequestResend *resend;
    [self.requestIdList enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        JY_HttpRequestResend *resendItem = obj;
        if ([response.baseResponseModel.requestId isEqualToNumber:resendItem.requestId]) {
            resend = resendItem;
            *stop = YES;
        }
    }];
    return resend;
}
#pragma mark 获取分配ID
-(NSNumber*)getDispatchResendId
{
    if (_resendId == nil) {
        _resendId = @(1);
    } else {
        if ([_resendId integerValue] == NSIntegerMax) {
            _resendId = @(1);
        } else {
            _resendId = @([_resendId integerValue] + 1);
        }
    }
    return _resendId;
}

#pragma mark 获取URL
-(NSString*)getURLStringWithApi:(NSString*)api
{
    return [NSString stringWithFormat:@"%@%@",JY_APP_URL,api];
}
#pragma mark ---------- Click Event ----------

#pragma mark ---------- Delegate ----------

#pragma mark ---------- Lazy Load ----------

-(NSMutableArray *)requestIdList{
    if (!_requestIdList) {
        _requestIdList  = [[NSMutableArray alloc]init];
    }
    return _requestIdList;
}

@end
