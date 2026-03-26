// import 'dart:async';

// import 'package:meet/managers/providers/data.provider.manager.dart';
// import 'package:meet/models/address.dao.impl.dart';
// import 'package:meet/models/address.model.dart';

// class ProtonAddressProvider extends DataProvider {
//   /// dao
//   final AddressDao addressDao;

//   ProtonAddressProvider(
//     this.addressDao,
//   );

//   Future<AddressModel?> getAddressModel(String serverID) async {
//     final AddressModel? addressModel =
//         await addressDao.findByServerID(serverID);
//     return addressModel;
//   }

//   @override
//   Future<void> clear() async {}

//   @override
//   Future<void> reload() async {}
// }
