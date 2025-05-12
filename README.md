# WitWiz macOS


## How to generate swift files from proto

```
cp ../witwiz-server/proto/witwiz.proto ./libs/WitWizCl/Sources/WitWizCl

protoc --swift_out=. --swift_opt=Visibility=Public ./libs/WitWizCl/Sources/WitWizCl/witwiz.proto

protoc --grpc-swift_out=. ./libs/WitWizCl/Sources/WitWizCl/witwiz.proto
```