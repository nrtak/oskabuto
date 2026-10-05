import IdentityLookup

final class MessageFilterHandler: ILMessageFilterExtension, ILMessageFilterQueryHandling {
    func handle(_ queryRequest: ILMessageFilterQueryRequest, context: ILMessageFilterExtensionContext,
                completion: @escaping (ILMessageFilterQueryResponse) -> Void) {
        let response = ILMessageFilterQueryResponse()
        response.action = SafetyEngine.isJunk(queryRequest.messageBody ?? "") ? .junk : .none
        completion(response)
    }
}
