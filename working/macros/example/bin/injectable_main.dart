import 'package:macro_proposal/injectable.dart';

void main() {
  final component = DripCoffeeComponent(DripCoffeeModule());

  print(component.coffeeMaker());
}

abstract class Heater {}

@Injectable()
class ElectricHeater implements Heater {
  // TODO: This is required for now.
  ElectricHeater();
}

abstract class Pump {}

@Injectable()
class Thermosiphon implements Pump {
  final Heater heater;

  Thermosiphon(this.heater);
}

@Injectable()
class CoffeeMaker {
  final Heater heater;
  final Pump pump;

  CoffeeMaker(this.heater, this.pump);
}

class DripCoffeeModule {
  @Provides()
  Heater provideHeater(ElectricHeater impl) => impl;
  @Provides()
  Pump providePump(Thermosiphon impl) => impl;
}

@Component(modules: [])
class DripCoffeeComponent {
  external CoffeeMaker coffeeMaker();

  // TODO: Generate this from the modules given above once macro args are
  // supported.
  external factory DripCoffeeComponent(DripCoffeeModule dripCoffeeModule);
}
