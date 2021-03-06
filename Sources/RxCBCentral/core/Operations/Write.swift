//
//  Copyright (c) 2019 Uber Technologies, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreBluetooth
import Foundation
import RxSwift

public typealias SingleTransformer<E, R> = (Single<E>) -> Single<R>

/// Basic write, completes after the underlying write chunks have all been completed.
public class Write: GattOperation {
    public lazy var result: Single<()> =
        write(service: service, characteristic: characteristic, data: data)
            .compose(postWrite)
            .asObservable()
            .share()
            .take(1)
            .asSingle()
            .timeout(timeoutSeconds, scheduler: scheduler)
    
    public convenience init(service: CBUUID, characteristic: CBUUID, data: Data) {
        self.init(service: service, characteristic: characteristic, data: data, timeoutSeconds: GattConstants.defaultOperationTimeout)
    }
    
    public init(service: CBUUID, characteristic: CBUUID, data: Data, timeoutSeconds: RxTimeInterval, scheduler: SchedulerType = SerialDispatchQueueScheduler(qos: .utility)) {
        self.service = service
        self.characteristic = characteristic
        self.data = data
        self.timeoutSeconds = timeoutSeconds
        self.scheduler = scheduler
    }
    
    public func execute(with peripheral: RxPeripheral) {
        _peripheralSubject.onNext(peripheral)
    }
    
    func write(service: CBUUID, characteristic: CBUUID, data: Data) -> Single<RxPeripheral> {
        return _peripheralSubject
            .flatMap({ (rxPeripheral) -> Observable<RxPeripheral> in
                var chunkCompletables: [Completable] = []
                let byteArray = [UInt8](data)
                
                byteArray.forEachChunk(by: rxPeripheral.maxWriteLength) { chunk in
                    chunkCompletables.append(rxPeripheral.write(service: service, characteristic: characteristic, data: Data(chunk)))
                }
                
                return Completable.concat(chunkCompletables).andThen(Observable.just(rxPeripheral))
            })
            .take(1)
            .asSingle()
    }
    
    private var postWrite: SingleTransformer<RxPeripheral, Element> {
        return { single in
            single.flatMap {
                _ in Single.just(())
            }
        }
    }
    
    private let _peripheralSubject = ReplaySubject<RxPeripheral>.create(bufferSize: 1)
    
    private let service: CBUUID, characteristic: CBUUID, data: Data, timeoutSeconds: RxTimeInterval, scheduler: SchedulerType
}

extension Array where Element == UInt8 {
    func forEachChunk(by size: Int, _ body: ([Element]) -> ()) {
        stride(from: 0, to: count, by: size).forEach { index in
            body(Array(self[index ..< Swift.min(index + size, count)]))
        }
    }
}

extension Single where Trait == SingleTrait {
    func compose<R>(_ transformer: SingleTransformer<Element, R>) -> Single<R> {
        return transformer(self)
    }
}
